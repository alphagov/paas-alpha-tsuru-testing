require 'open-uri'
require 'tsuru_helper.rb'

RSpec.configure do |c|
  c.add_setting :debug_commands, :default => false

  c.add_setting :deploy_env, :default => ENV['DEPLOY_ENV'] || 'ci'

  c.add_setting :target_platform, :default => ENV['TARGET_PLATFORM'] || 'aws'

  # If nil will be populated based on the default platform
  c.add_setting :target_api_host, :default =>
    case c.target_platform
    when 'aws'
      "#{RSpec.configuration.deploy_env}-api.tsuru.paas.alphagov.co.uk"
    when 'gce'
      "#{RSpec.configuration.deploy_env}-api.tsuru2.paas.alphagov.co.uk"
    else
      raise "Unknown target_platform = #{c.target_platform}"
    end

  c.add_setting :tsuru_user, :default => ENV['TSURU_USER']
  c.add_setting :tsuru_pass, :default => ENV['TSURU_PASS']

end

describe "TsuruEndToEnd" do
  context "deploying an application" do
    before(:all) do
      @tsuru_home = Tempdir.new('tsuru-command')
      @tsuru_command = TsuruCommandLine.new({ 'HOME' => @tsuru_home.path })

      @tsuru_api_url = "https://#{RSpec.configuration.target_api_host}"
      @tsuru_api_url_insecure = "http://#{RSpec.configuration.target_api_host}:8080"

      @tsuru_command.target_add("ci", @tsuru_api_url)
      @tsuru_command.target_add("ci-insecure", @tsuru_api_url_insecure)

      @tsuru_user = RSpec.configuration.tsuru_user || raise("You must set 'TSURU_USER' env var")
      @tsuru_pass = RSpec.configuration.tsuru_pass || raise("You must set 'TSURU_PASS' env var")

      # Clone the same app and setup minigit
      @sampleapp_path = File.join(@tsuru_home, 'sampleapp')
      minigit_class = MiniGitStdErrCapturing
      minigit_class.git :clone, "https://github.com/alphagov/flask-sqlalchemy-postgres-heroku-example.git", @sampleapp_path
      @sampleapp_minigit = minigit_class.new(@sampleapp_path)

      # Generate the ssh key and setup ssh
      @ssh_id_rsa_path = File.join(@tsuru_home, '.ssh', 'id_rsa')
      @ssh_id_rsa_pub_path = File.join(@tsuru_home, '.ssh', 'id_rsa.pub')
      SshHelper.generate_key(@ssh_id_rsa_path)
      SshHelper.write_config(File.join(@tsuru_home, '.ssh', 'config'),
                             { "StrictHostKeyChecking" => "no" } )
    end

    after(:each) do |example|
      if example.exception
        # TODO improve how we print the output
        puts "$ #{@tsuru_command.last_command}"
        puts @tsuru_command.stdout
        puts @tsuru_command.stderr
      end
    end

    it "should not be able to login via HTTP" do
      @tsuru_command.target_set("ci-insecure")
      @tsuru_command.login(@tsuru_user, @tsuru_pass)
      expect(@tsuru_command.exit_status).not_to eql 0
    end

    it "should be able to login via HTTPS" do
      @tsuru_command.target_set("ci")
      @tsuru_command.login(@tsuru_user, @tsuru_pass)
      expect(@tsuru_command.exit_status).to eql 0
    end

    it "should clean up the environment" do
      @tsuru_command.key_remove('rspec') # Remove previous state if needed
      @tsuru_command.service_unbind('sampleapptestdb', 'sampleapp')
      @tsuru_command.service_remove('sampleapptestdb') # Remove previous state if needed
      @tsuru_command.app_remove('sampleapp') # Remove previous state if needed
      # Wait for the app to get deleted.
      # TODO: Improve this, implement some pooling logic.
      sleep(1)
    end

    it "should be able to add the ssh key" do
      @tsuru_command.key_add('rspec', @ssh_id_rsa_pub_path)
      expect(@tsuru_command.exit_status).to eql 0
      expect(@tsuru_command.stdout).to match /Key .* successfully added!/
    end

    it "should be able to create an application" do
      @tsuru_command.app_create('sampleapp', 'python')
      expect(@tsuru_command.exit_status).to eql 0
      expect(@tsuru_command.stdout).to match /App .* has been created/
    end

    it "should be able to create a service" do
      @tsuru_command.service_add('postgresql', 'sampleapptestdb', 'shared')
      expect(@tsuru_command.exit_status).to eql 0
      expect(@tsuru_command.stdout).to match /Service successfully added/
    end

    it "should be able to bind a service to an app" do
      @tsuru_command.service_bind('sampleapptestdb', 'sampleapp')
      expect(@tsuru_command.exit_status).to eql 0
      expect(@tsuru_command.stdout).to match /Instance .* is now bound to the app .*/
    end

    it "Should be able to push the application" do
      git_url = @tsuru_command.get_app_repository('sampleapp')
      expect(git_url).not_to be_nil
      @sampleapp_minigit.push(git_url, 'master')
      # Wait for the app to get deployed.
      # TODO: Implement some pooling logic.
      sleep(5)
    end

    it "Should be able to connect to the applitation via HTTPS" do
      sampleapp_address = @tsuru_command.get_app_address('sampleapp')
      response = URI.parse("https://#{sampleapp_address}/").open({ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE})
      expect(response.status).to eq(["200", "OK"])
    end
  end
end


