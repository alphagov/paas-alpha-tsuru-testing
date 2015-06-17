require 'open3'

# Wrapper around the TerraformCommandLine
class TerraformCommandLine
  attr_reader :exit_status, :stderr, :stdout, :last_command
  attr_reader :env, :terraform_path, :terraform_target

  def initialize(terraform_path = '.', terraform_target = 'ci', env = {})
    @env = env
    @terraform_target = terraform_target
    @terraform_path = terraform_path
  end

  def taint(resource_name)
    execute_helper('taint', resource_name)
  end

  def apply()
    execute_helper('apply', '-var',  "env=#{@terraform_target}")
  end

  def output(variable_name)
    if execute_helper('output', variable_name)
      stdout.strip
    else
      nil
    end
  end

  private

  def execute_helper(*cmd)
    @exit_status=nil
    @stderr=""
    @stdout=""

    # popen3 argument parsing is a little bit weird. In order to pass
    # environments and options we need to pass this format of argument:
    #     [env, cmdname, arg1, ..., opts]
    #
    # More info: http://www.rubydoc.info/stdlib/open3/Open3
    # popen3_args = [@env] + ["terraform"] + cmd + [{ :chdir => @terraform_path }]
    cmd.insert(0,'terraform')
    p "cd #{@terraform_path}; #{cmd.join(' ')}"
    Open3.popen3(@env, *cmd, { :chdir => @terraform_path }) do |stdin, out, err, wait_thread|
      # Allow additional preprocessing of the system call if the caller passes a block
      yield(stdin, out, err, wait_thread) if block_given?
      stdin.close
      Thread.new do
        out.each {|l|
          puts "o> #{l}"
          @stdout << l
        }
      end
      Thread.new do
        err.each {|l|
          puts "e> #{l}"
          @stderr << l
        }
      end
      [stdin, out, err].each{|stream| stream.close() if not stream.closed? }
      @exit_status = wait_thread.value.to_i
      p @stdout
      p @stderr
    end
    return @exit_status == 0
  end
end
