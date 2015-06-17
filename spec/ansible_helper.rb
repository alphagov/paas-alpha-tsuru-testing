require 'open3'

# Wrapper around the TerraformCommandLine
class AnsibleCommandLine
  attr_reader :exit_status, :stderr, :stdout, :last_command
  attr_reader :env, :terraform_path

  def initialize(ansible_path = '.', env = {})
    @env = env
    @ansible_path = ansible_path
  end

  def make(platform_name, target_environment, limit=[])
    execute_helper('make', platform_name, "ARGS=-l #{limit.join(',')}")
  end

  private

  def execute_helper(*cmd)
    @exit_status=nil
    @stderr=nil
    @stdout=nil

    # popen3 argument parsing is a little bit weird. In order to pass
    # environments and options we need to pass this format of argument:
    #     [env, cmdname, arg1, ..., opts]
    #
    # More info: http://www.rubydoc.info/stdlib/open3/Open3
    # popen3_args = [@env] + ["terraform"] + cmd + [{ :chdir => @terraform_path }]
    Open3.popen3(@env, *cmd, { :chdir => @ansible_path }) do |stdin, out, err, wait_thread|
      # Allow additional preprocessing of the system call if the caller passes a block
      yield(stdin, out, err, wait_thread) if block_given?

      @stdout = out.readlines().join
      @stderr = err.readlines().join
      [stdin, out, err].each{|stream| stream.close() if not stream.closed? }
      @exit_status = wait_thread.value.to_i
    end
    return @exit_status == 0
  end
end

