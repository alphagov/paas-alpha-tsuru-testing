require 'git_helper.rb'
require 'tsuru_helper.rb'
require 'terraform_helper.rb'
require 'ansible_helper.rb'

describe "TsuruRegistry" do
  context "reprovisioning a docker registry" do
    before(:all) do
      # tsuru command setup
      @tsuru_home = Tempdir.new('tsuru-command')
      @tsuru_command = TsuruCommandLine.new({ 'HOME' => @tsuru_home.path })

      @tsuru_api_url = "https://#{RSpec.configuration.target_api_host}"

      @tsuru_user = RSpec.configuration.tsuru_user || raise("You must set 'TSURU_USER' env var")
      @tsuru_pass = RSpec.configuration.tsuru_pass || raise("You must set 'TSURU_PASS' env var")

      # Terraform command setup
      # TODO: Parametrise the terraform dir
      @terraform_command = TerraformCommandLine.new(
        "/Users/keymon/gds/tsuru-terraform/aws",
        RSpec.configuration.deploy_env,
        { 'HOME' => @tsuru_home.path })

      # Ansible command setup
      # TODO: Parametrise the ansible dir
      @ansible_command = AnsibleCommandLine.new(
        "/Users/keymon/gds/tsuru-ansible/",
        { 'HOME' => @tsuru_home.path,
          'TARGET_ENV' => RSpec.configuration.deploy_env })

    end

    after(:each) do |example|
      if example.exception
        # TODO improve how we print the output
        puts "$ #{@tsuru_command.last_command}"
        puts @tsuru_command.stdout
        puts @tsuru_command.stderr

        puts "$ #{@terraform_command.last_command}"
        puts @terraform_command.stdout
        puts @terraform_command.stderr
      end
    end

    it "Should be able to setup the workspace" do
      # TODO: Fail if any step here fails
      @tsuru_command.target_add("mytarget", @tsuru_api_url)
      expect(@tsuru_command.exit_status).to eql 0
      @tsuru_command.target_set("mytarget")
      expect(@tsuru_command.exit_status).to eql 0
      @tsuru_command.login(@tsuru_user, @tsuru_pass)
      expect(@tsuru_command.exit_status).to eql 0
      # clean up
      @tsuru_command.key_remove('rspec')
      @tsuru_command.service_unbind('sampleapptestdb', 'sampleapp')
      @tsuru_command.service_remove('sampleapptestdb')
      @tsuru_command.app_remove('sampleapp')
      # Setup the key
      ssh_id_rsa_path = File.join(@tsuru_home.path, '.ssh', 'id_rsa')
      ssh_id_rsa_pub_path = File.join(@tsuru_home.path, '.ssh', 'id_rsa.pub')
      SshHelper.generate_key(ssh_id_rsa_path)
      SshHelper.write_config(File.join(@tsuru_home.path, '.ssh', 'config'),
                             { "StrictHostKeyChecking" => "no" } )
      @tsuru_command.key_add('rspec', ssh_id_rsa_pub_path)
      expect(@tsuru_command.exit_status).to eql 0

      # Create the app
      @tsuru_command.app_create('sampleapp', 'python')
      expect(@tsuru_command.exit_status).to eql 0
      @tsuru_command.service_add('postgresql', 'sampleapptestdb', 'shared')
      expect(@tsuru_command.exit_status).to eql 0
      @tsuru_command.service_bind('sampleapptestdb', 'sampleapp')
      expect(@tsuru_command.exit_status).to eql 0
    end

    it "Should be able to push the application" do
      # Clone the same app and setup minigit
      @sampleapp_path = File.join(@tsuru_home.path, 'sampleapp')
      # minigit_class = MiniGitStdErrCapturing
      minigit_class = MiniGit
      minigit_class.git :clone, "https://github.com/alphagov/flask-sqlalchemy-postgres-heroku-example.git", @sampleapp_path

      @sampleapp_minigit = minigit_class.new(@sampleapp_path)
      ENV['GIT_SSH_COMMAND']="ssh -i #{@tsuru_home.path}/.ssh/id_rsa -v"

      @sampleapp_minigit.git_command="/usr/local/bin/git"

      # Deploy the app
      git_url = @tsuru_command.get_app_repository('sampleapp')
      expect(git_url).not_to be_nil
      @sampleapp_minigit.push(git_url, 'master')
      # Wait for the app to get deployed.
      # TODO: Implement some pooling logic.
      sleep(5)
    end

    it "Should be able to restart the application if registry has been reprovision" do
      @terraform_command.taint('aws_instance.docker-registry')
      expect(@terraform_command.exit_status).to eql 0
      @terraform_command.apply()
      expect(@terraform_command.exit_status).to eql 0
      @ansible_command.make('aws', ['*tsuru-registry*'])
      expect(@ansible_command.exit_status).to eql 0
      @tsuru_command.restart('sample_app')
      expect(@tsuru_command.exit_status).to eql 0
    end

  end
end

