# DevEnvMonitor

概要

DevEnvMonitorは、開発環境でのリソース使用状況とSQLクエリのパフォーマンスをリアルタイムで監視するためのツールです。SinatraベースのWebアプリケーションとして動作し、WebSocketを使用して最新のメトリクスをブラウザに表示します。

主な機能

1.	CPU使用率の監視
	•	システムのCPU負荷を監視し、使用率とアイドル状態をリアルタイムで表示します。
2.	メモリ使用状況の監視
	•	システムのメモリ使用状況を監視し、総メモリ、使用メモリ、および空きメモリの量を表示します。
3.	ディスク使用状況の監視
	•	システムのディスク使用状況を監視し、総ディスク容量、使用ディスク容量、および空きディスク容量を表示します。
4.	プロセス情報の監視
	•	Rails、Ruby、Pumaなどのプロセス情報を収集し、プロセスID、コマンドライン、説明を表示します。
5.	SQLクエリの監視
	•	ActiveRecordのSQLクエリをキャプチャし、実行時間、キャッシュされたクエリかどうか、クエリの発行元などの詳細を表示します。
	•	クエリのパフォーマンス問題（例：N+1クエリ）を検出し、警告を表示します。
6.	リアルタイム更新
	•	WebSocketを使用して、3秒ごとに最新のメトリクスをブラウザにプッシュし、ユーザーインターフェースをリアルタイムで更新します。

技術スタック

	•	Sinatra: 軽量なRubyのWebフレームワークを使用してWebアプリケーションを構築。
	•	WebSocket: クライアントとサーバー間のリアルタイム通信を実現。
	•	Sys::CPU, Sys::ProcTable, Sys::Filesystem: システムリソース情報を収集するためのライブラリ。
	•	ActiveSupport::Notifications: RailsのSQLクエリをキャプチャするために使用。
	•	Logger: ログの記録とデバッグ情報の出力に使用。

導入と使用方法

1.	インストール: Gemfileにdev_env_monitorを追加し、bundle installを実行。
2.	設定: config/environments/development.rbにrequire_relativeを追加して、DevEnvMonitorを初期化。
3.	起動: ProcfileでLAUNCH_DEV_ENV_MONITOR環境変数を設定して、Foremanを使用して起動。
4.	アクセス: ブラウザでhttp://localhost:4567にアクセスして、監視ダッシュボードを確認。
