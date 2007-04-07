class BootstrapRspec
  attr_reader :rake
  def initialize(rake)
    @rake = rake
  end

  def pre_commit
    begin
      rm_rf 'vendor/plugins/rspec_on_rails'
      silent_sh "svn export ../rspec_on_rails vendor/plugins/rspec_on_rails"

      create_purchase unless ENV['RSPEC_RAILS_VERSION'] == '1.1.6'
      ensure_db_config
      clobber_sqlite_data
      run_pre_commit_task "db:migrate", true
      generate_rspec
      run_pre_commit_task "spec", true
      run_pre_commit_task "spec:plugins", true
      run_pre_commit_task "rspec:destroy_purchase", true
    ensure
      rm_rf 'vendor/plugins/rspec_on_rails'
    end
  end

  def create_purchase
    generate_purchase
    run_pre_commit_task 'rspec:migrate_up', true
  end

  def install_plugin
    rm_rf 'vendor/plugins/rspec_on_rails'
    puts "installing rspec_on_rails ..."
    result = silent_sh("svn export ../rspec_on_rails vendor/plugins/rspec_on_rails")
    raise "Failed to install plugin:\n#{result}" if error_code?
  end

  def uninstall_plugin
    rm_rf 'vendor/plugins/rspec_on_rails'
  end

  def generate_rspec
    result = silent_sh("ruby script/generate rspec --force")
    raise "Failed to generate rspec environment:\n#{result}" if error_code? || result =~ /^Missing/
  end

  def ensure_db_config
    config_path = 'config/database.yml'
    unless File.exists?(config_path)
      message = <<-EOF
      #####################################################
      Could not find #{config_path}

      You can get rake to generate this file for you using either of:
        rake rspec:generate_mysql_config
        rake rspec:generate_sqlite3_config

      If you use mysql, you'll need to create dev and test
      databases and users for each. To do this, standing
      in rspec_on_rails, log into mysql as root and then...
        mysql> source db/mysql_setup.sql;

      There is also a teardown script that will remove
      the databases and users:
        mysql> source db/mysql_teardown.sql;
      #####################################################
      EOF
      raise message.gsub(/^      /, '')
    end
  end

  def generate_mysql_config
    copy 'config/database.mysql.yml', 'config/database.yml'
  end

  def generate_sqlite3_config
    copy 'config/database.sqlite3.yml', 'config/database.yml'
  end

  def clobber_db_config
    rm 'config/database.yml'
  end

  def clobber_sqlite_data
    rm_rf 'db/*.db'
  end

  def generate_purchase
    generator = "ruby script/generate rspec_resource purchase order_id:integer created_at:datetime amount:decimal keyword:string description:text --force"
    notice = <<-EOF
    #####################################################
    #{generator}
    #####################################################
    EOF
    puts notice.gsub(/^    /, '')
    result = silent_sh(generator)
    raise "rspec_resource failed. #{result}" if error_code? || result =~ /not/
  end

  def migrate_up
    ENV['VERSION'] = '5'
    Rake::Task["db:migrate"].invoke
  end

  def destroy_purchase
    run_pre_commit_task "rspec:migrate_down", true
    rm_generated_purchase_files
  end

  def migrate_down
    notice = <<-EOF
    #####################################################
    Migrating down and reverting config/routes.rb
    #####################################################
    EOF
    puts notice.gsub(/^    /, '')
    ENV['VERSION'] = '4'
    Rake::Task["db:migrate"].invoke
    output = silent_sh("svn revert config/routes.rb")
    raise "svn revert failed: #{output}" if error_code?
  end

  def rm_generated_purchase_files
    puts "#####################################################"
    puts "Removing generated files:"
    generated_files = %W{
      app/helpers/purchases_helper.rb
      app/models/purchase.rb
      app/controllers/purchases_controller.rb
      app/views/purchases
      db/migrate/005_create_purchases.rb
      spec/models/purchase_spec.rb
      spec/controllers/purchases_controller_spec.rb
      spec/fixtures/purchases.yml
      spec/views/purchases
    }
    generated_files.each do |file|
      rm_rf file
    end
    puts "#####################################################"
  end

  def run_pre_commit_task(task_name, external_process=false)
    if external_process
      output = silent_sh("rake #{task_name} --trace") do |line|
        puts line unless line =~ /^running against rails/ || line =~ /^\(in /
      end
      raise "ERROR while running rake: #{output}" if output =~ /ERROR/n || error_code?
    else
      Rake::Task[task_name].invoke
    end
  end

  protected
  def silent_sh(cmd, &block)
    output = nil
    IO.popen(cmd) do |io|
      io.each_line do |line|
        block.call(line) if block
      end
      output = io.read
    end
    output
  end

  def error_code?
    $? != 0
  end

  def method_missing(method_name, *args, &block)
    if rake.respond_to?(method_name)
      rake.send(method_name, *args, &block)
    else
      super
    end
  end
end
