# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "dev_env_monitor"
  spec.version       = "0.1.0"
  spec.authors       = ["Your Name"]
  spec.email         = ["your.email@example.com"]

  spec.summary       = %q{DevEnvMonitor is a tool to monitor development environment resources in real-time.}
  spec.description   = %q{DevEnvMonitor monitors CPU usage, memory usage, disk usage, and SQL queries in real-time, providing a web interface for viewing the data.}
  spec.homepage      = "http://example.com/dev_env_monitor"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "sinatra"
  spec.add_dependency "sinatra-websocket"
  spec.add_dependency "thin"
  spec.add_dependency "sys-proctable"
  spec.add_dependency "sys-cpu"
  spec.add_dependency "sys-filesystem"
end
