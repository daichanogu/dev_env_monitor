# frozen_string_literal: true

require 'dotenv/load'
require 'byebug'
require 'pry'
require 'pry-byebug'
require 'sinatra/base'
require 'sinatra-websocket'
require 'sys/proctable'
require 'sys/cpu'
require 'sys/filesystem'
require 'json'
require 'thread'
require 'active_record'
require 'active_support/notifications'
require 'logger'

module DevEnvMonitor
  class Monitor
    include Singleton

    def initialize
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::DEBUG
      @cpu_info = Sys::CPU
      @process_info = Sys::ProcTable
      @filesystem_info = Sys::Filesystem
      @sql_queries = []
      setup_sql_capture unless defined?(@subscribed)
      setup_periodic_update
    end

    def cpu_usage
      cpu_info = `top -l 1 -n 0 | grep 'CPU usage'`
      cpu_user = cpu_info[/(\d+\.\d+)% user/, 1].to_f
      cpu_sys = cpu_info[/(\d+\.\d+)% sys/, 1].to_f
      cpu_idle = cpu_info[/(\d+\.\d+)% idle/, 1].to_f

      used_percentage = cpu_user + cpu_sys
      idle_percentage = cpu_idle

      { capacity: 100, used: used_percentage.round(2), idle: idle_percentage.round(2) }
    end

    def memory_usage
      vm_stat = `vm_stat`
      pagesize = `sysctl -n hw.pagesize`.to_i
      free_memory = vm_stat[/Pages free:\s+(\d+)/, 1].to_i * pagesize # free
      speculative_memory = vm_stat[/Pages speculative:\s+(\d+)/, 1].to_i * pagesize # free, speculative
      inactive_memory = vm_stat[/Pages inactive:\s+(\d+)/, 1].to_i * pagesize # used, file cache
      active_memory = vm_stat[/Pages active:\s+(\d+)/, 1].to_i * pagesize # used, app_memory
      wired_memory = vm_stat[/Pages wired down:\s+(\d+)/, 1].to_i * pagesize # used, wired
      compressed_memory = vm_stat[/Pages occupied by compressor:\s+(\d+)/, 1].to_i * pagesize # used, compressed

      used_memory = active_memory + inactive_memory + wired_memory + compressed_memory
      free_memory_total = free_memory + speculative_memory
      total_memory = used_memory + free_memory_total

      { total: to_gb(total_memory), used: to_gb(used_memory), free: to_gb(free_memory_total) }
    end

    def disk_usage
      stat = @filesystem_info.stat('/')
      total = stat.blocks * stat.block_size
      used = (stat.blocks - stat.blocks_free) * stat.block_size
      { total: to_gb(total), used: to_gb(used), free: to_gb(total - used) }
    end

    def process_info
      processes = @process_info.ps
      processes.select { |p| p.cmdline.include?('rails') || p.cmdline.include?('ruby') || p.cmdline.include?('puma') }.map do |p|
        next if p.cmdline.include?('fsevent_watch')
        {
          pid: p.pid,
          comm: p.comm,
          cmdline: p.cmdline,
          description: describe_process(p.cmdline)
        }
      end.compact
    end

    def describe_process(cmdline)
      case cmdline
      when /puma/
        "Puma サーバー (Rails アプリケーションをホスト)"
      when /rails/
        "Rails プロセス"
      when /dev_env_monitor/
        "Ruby プロセス (dev_env_monitor)"
      else
        "不明なプロセス"
      end
    end

    def monitor_all
      {
        cpu_usage: cpu_usage,
        memory_usage: memory_usage,
        disk_usage: disk_usage,
        process_info: process_info,
        sql_queries: @sql_queries
      }
    end

    def metrics_all
      {
        cpu_usage: cpu_usage,
        memory_usage: memory_usage,
        disk_usage: disk_usage,
        process_info: process_info
      }
    end

    def debugging?
      defined?(Pry) && Thread.list.any? { |thr| thr.backtrace&.any? { |line| line.include?('pry') } } ||
      defined?(Byebug) && Thread.list.any? { |thr| thr.backtrace&.any? { |line| line.include?('byebug') } }
    end

    private

    def setup_sql_capture
      ActiveSupport::Notifications.subscribe('sql.active_record') do |name, started, finished, unique_id, payload|
        process_sql_event(name, started, finished, payload)
      end
      @subscribed = true
    end

    def setup_periodic_update
      Thread.new do
        loop do
          sleep 3 # 3秒ごとに更新
          unless debugging?
            EM.next_tick { broadcast_update }
          end
        end
      end
    end

    def process_sql_event(name, started, finished, payload)
      duration = ((finished - started) * 1000).round(2)
      sql = payload[:sql]
      cached = payload[:cached] || false
      location = Rails.backtrace_cleaner.clean(caller.lazy).first

      # クエリ解析ロジック（簡易版）
      warning, message = analyze_sql_for_performance_issues(sql)

      sql_entry = {
        timestamp: started.strftime('%H:%M:%S:%L'),
        duration: duration,
        sql: sql,
        cached: cached,
        location: location,
        warning: warning,
        message: message
      }

      # 重複チェック
      unless @sql_queries.include?(sql_entry)
        @sql_queries << sql_entry
        @sql_queries.shift if @sql_queries.size > 100
        notify_sql_query({ sql_query: @sql_queries.last })
      end
    end

    def analyze_sql_for_performance_issues(sql)
      # 疑わしいパターンが見つかった場合に警告
      if sql.match(/SELECT .* FROM .* WHERE .*/i) && !sql.include?("JOIN")
        return [true, "N+1クエリの可能性があります。関連データの事前読み込みを検討してください。"]
      end
      [false, ""]
    end

    def broadcast_update
      DevEnvMonitor::WebApp.notify(metrics_all.to_json)
    end

    def notify_sql_query(sql)
      unless debugging?
        DevEnvMonitor::WebApp.notify(sql.to_json)
      end
    end

    def to_gb(bytes)
      (bytes / 1024.0 / 1024.0 / 1024.0).round(2)
    end
  end

  class WebApp < Sinatra::Base
    set :server, 'thin'
    set :sockets, []
    set :views, File.expand_path('views', __dir__)
    set :public_folder, File.expand_path('public', __dir__)

    get '/' do
      if !request.websocket?
        erb :index
      else
        request.websocket do |ws|
          ws.onopen do
            settings.sockets << ws
            ws.send('Connected'.dup.force_encoding('BINARY'))
          end

          ws.onmessage do |msg|
            # puts "Received message: #{msg}"
            monitor = DevEnvMonitor::Monitor.instance
            unless monitor.debugging?
              data = monitor.monitor_all.to_json
              # puts "Sending data: #{data}"
              EM.next_tick do
                settings.sockets.each { |s| s.send(data) }
                puts "Sent monitor data to WebSocket clients"
              end
            else
              puts "Debug session is active. Skipping sending monitor data to WebSocket clients"
            end
          end

          ws.onclose do
            settings.sockets.delete(ws)
          end
        end
      end
    end

    def self.notify(data)
      settings.sockets.each { |s| s.send(data) }
    end

    run! if app_file == $PROGRAM_NAME
  end

  def self.start_server
    if ENV['LAUNCH_DEV_ENV_MONITOR'] == 'true'
      Thread.new do
        WebApp.run! port: 4567, bind: '0.0.0.0'
      end
      puts 'DevEnvMonitor is running. Open http://localhos:4567 in your browser.'
    else
      puts 'DevEnvMonitor cannot start because the LAUNCH_DEV_ENV_MONITOR environment variable is not set.'
    end
  end
end

DevEnvMonitor.start_server
