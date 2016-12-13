# 没有指定环境的话默认在开发环境下运行
env = ENV["RAILS_ENV"] || "development"

# 需要开启的unicorn worker进程数，详见：http://unicorn.bogomips.org/Unicorn/Configurator.html.
worker_processes 4

# app相关设置
# app工作路径，默认向上找两级路径，即projects/config/unicorn.rb
app_dir = File.expand_path("../..", __FILE__)

# 应用名称（项目根目录名）
app_name = "deploy"

# 保存unicorn进程id的文件路径，重要，确保当前用户有访问此文件的权限
pid_path = "#{app_dir}/tmp/pids/unicorn.#{app_name}.pid"

# nginx与unicorn进行socket通信的文件路径，重要，确保当前用户有访问此文件的权限
sock_path = "#{app_dir}/tmp/sockets/unicorn.#{app_name}.sock"

# 监听socket文件，也可以在此处指定一个端口号
# 减小backlog的长度以得到更快的速度（这里理解的不深，先把原文留下了：we use a shorter backlog for quicker failover when busy）
listen sock_path, :backlog => 64

# 销毁worker的时间改为30s，默认为60
timeout 30

# 指定pid保存路径
pid pid_path

# Production环境下的特殊配置，即网站发布之后的服务器端配置
if env == "production"
  # Help ensure your application will always spawn in the symlinked
  # "current" directory that Capistrano sets up.

  # 指定production下的工作路径为current，项目自动发布（deploy）到服务器上的时候，capistrano会将当前工作的站点放在current路径下，在后续deploy的时候会详细讲到。
  working_directory "#{app_dir}/current"

  # production环境下运行的用户和组，确保这个用户有访问app_dir、socket、pid路径的权限
  user 'deploy', 'deploy'

  # share目录，每次发布时不需要改变或者无法改变的文件会放在这个目录下，如log等，deploy中会讲到
  shared_path = "#{app_dir}/current/shared"

  # unicorn的错误和输出日志
  stderr_path "#{shared_path}/log/unicorn.stderr.log"
  stdout_path "#{shared_path}/log/unicorn.stdout.log"
end

# 在创建fork process之前预加载app以得到更快的启动速度，但这样的话必须保证其他的连接（如数据库连接）都被正确的关闭和重启，于是就用到了before_fork和after_fork
preload_app true

# unicorn通过fork processes来实现多进程，因此需要在before_fork和after_fork配置数据库连接的关闭和重启。
before_fork do |server, worker|
  # the following is highly recomended for Rails + "preload_app true"
  # as there's no need for the master process to hold a connection
  if defined?(ActiveRecord::Base)
    ActiveRecord::Base.connection.disconnect!
  end

  # 杀掉位于 .oldbin 这个PID上的master进程.
  # deploy的时候很有用，可以实现rails服务的zero downtime重启
  old_pid = "#{pid_path}.oldbin"
  if File.exists?(old_pid) && server.pid != old_pid
    begin
      Process.kill("QUIT", File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
      # someone else did our job for us
    end
  end
end

after_fork do |server, worker|
  # the following is *required* for Rails + "preload_app true",
  if defined?(ActiveRecord::Base)
    ActiveRecord::Base.establish_connection
  end

  # if preload_app is true, then you may also want to check and
  # restart any other shared sockets/descriptors such as Memcached,
  # and Redis.  TokyoCabinet file handles are safe to reuse
  # between any number of forked children (assuming your kernel
  # correctly implements pread()/pwrite() system calls)
end