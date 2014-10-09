#  Phusion Passenger - https://www.phusionpassenger.com/
#  Copyright (c) 2014 Phusion
#
#  "Phusion Passenger" is a trademark of Hongli Lai & Ninh Bui.
#
#  Permission is hereby granted, free of charge, to any person obtaining a copy
#  of this software and associated documentation files (the "Software"), to deal
#  in the Software without restriction, including without limitation the rights
#  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#  copies of the Software, and to permit persons to whom the Software is
#  furnished to do so, subject to the following conditions:
#
#  The above copyright notice and this permission notice shall be included in
#  all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#  THE SOFTWARE.

require 'optparse'
require 'logger'
PhusionPassenger.require_passenger_lib 'constants'
PhusionPassenger.require_passenger_lib 'platform_info'
PhusionPassenger.require_passenger_lib 'config/command'
PhusionPassenger.require_passenger_lib 'config/install_agent_command'
PhusionPassenger.require_passenger_lib 'config/download_nginx_engine_command'
PhusionPassenger.require_passenger_lib 'config/compile_nginx_engine_command'
PhusionPassenger.require_passenger_lib 'utils/ansi_colors'
PhusionPassenger.require_passenger_lib 'utils/tmpio'

module PhusionPassenger
module Config

class InstallStandaloneRuntimeCommand < Command
	def run
		@options = {
			:log_level => Logger::INFO,
			:colorize => :auto,
			:force => false,
			:force_tip => true,
			:install_agent => true,
			:install_agent_args => [],
			:download_args => [
				"--no-error-colors",
				"--no-compilation-tip"
			],
			:compile_args => []
		}
		parse_options
		initialize_objects
		sanity_check
		PhusionPassenger::Utils.mktmpdir("passenger-install.", PlatformInfo.tmpexedir) do |tmpdir|
			install_agent(tmpdir)
			if !download_nginx_engine
				compile_nginx_engine(tmpdir)
			end
		end
	end

private
	def self.create_option_parser(options)
		OptionParser.new do |opts|
			nl = "\n" + ' ' * 37
			opts.banner = "Usage: passenger-config install-standalone-runtime [OPTIONS]\n"
			opts.separator ""
			opts.separator "  Install the #{PROGRAM_NAME} Standalone runtime. This runtime consists of"
			opts.separator "  the #{PROGRAM_NAME} agent, and an Nginx engine. Installation is done either"
			opts.separator "  by downloading the necessary files from the #{PROGRAM_NAME} website, or"
			opts.separator "  by compiling them from source."
			opts.separator ""

			opts.separator "Options:"
			opts.on("--working-dir PATH", String, "Store temporary files in the given#{nl}" +
				"directory, instead of creating one") do |val|
				options[:install_agent_args] << "--working-dir"
				options[:install_agent_args] << val
				options[:compile_args] << "--working-dir"
				options[:compile_args] << val
			end
			opts.on("--url-root URL", String, "Download binaries from a custom URL") do |value|
				options[:install_agent_args] << "--url-root"
				options[:install_agent_args] << value
				options[:download_args] << "--url-root"
				options[:download_args] << value
			end
			opts.on("--nginx-version VERSION", String, "Nginx version to compile. " +
				"Default: #{PREFERRED_NGINX_VERSION}") do |val|
				options[:nginx_version] = val
			end
			opts.on("--nginx-tarball PATH", String, "Use the given Nginx tarball instead of#{nl}" +
				"downloading it. You MUST also specify the#{nl}" +
				"Nginx version with --nginx-version") do |val|
				options[:nginx_tarball] = val
			end
			opts.on("--brief", "Report progress in a brief style") do
				options[:brief] = true
				options[:install_agent_args] << "--brief"
				options[:download_args] << "--log-level"
				options[:download_args] << "warn"
				options[:download_args] << "--log-prefix"
				options[:download_args] << "     "
				options[:download_args] << "--no-download-progress"
			end
			opts.on("-f", "--force", "Skip sanity checks") do
				options[:force] = true
				options[:install_agent_args] << "--force"
				options[:download_args] << "--force"
				options[:compile_args] << "--force"
			end
			opts.on("--no-force-tip", "Do not print any tips regarding the --force parameter") do
				options[:force_tip] = false
				options[:install_agent_args] << "--no-force-tip"
				options[:download_args] << "--no-force-tip"
				options[:compile_args] << "--no-force-tip"
			end
			opts.on("--skip-agent", "Do not install the agent") do
				options[:install_agent] = false
			end
			opts.on("--skip-cache", "Do not copy the binaries from cache") do
				options[:install_agent_args] << "--skip-cache"
				options[:download_args] << "--skip-cache"
			end
			opts.on("-h", "--help", "Show this help") do
				options[:help] = true
			end
		end
	end

	def help
		puts @parser
	end

	def initialize_objects
		@colors = Utils::AnsiColors.new(@options[:colorize])
		@logger = Logger.new(STDOUT)
		@logger.level = @options[:log_level]
		@logger.formatter = proc do |severity, datetime, progname, msg|
			if severity == "FATAL" || severity == "ERROR"
				color = @colors.red
			else
				color = nil
			end
			result = ""
			msg.split("\n", -1).map do |line|
				result << "#{color}#{@options[:log_prefix]}#{line}#{@colors.reset}\n"
			end
			result
		end
		if !@options[:nginx_version]
			if @options[:nginx_tarball]
				abort "#{@colors.red}Error: if you specify --nginx-tarball, " +
					"you must also specify --nginx-version.#{@colors.reset}"
			else
				@options[:nginx_version] = PREFERRED_NGINX_VERSION
			end
		end
	end

	def sanity_check
		return if @options[:force]

		all_installed = PhusionPassenger.find_support_binary(AGENT_EXE) &&
			PhusionPassenger.find_support_binary("nginx-#{@options[:nginx_version]}")
		if all_installed
			@logger.warn "#{@colors.green}The #{PROGRAM_NAME} Standalone runtime is already installed."
			if @options[:force_tip]
				@logger.warn "If you want to redownload it, re-run this program with the --force parameter."
			end
			exit
		end
	end

	def install_agent(tmpdir)
		if @options[:install_agent]
			args = @options[:install_agent_args].dup
			args << "--working-dir"
			args << tmpdir
			InstallAgentCommand.new(args).run
			puts
		end
	end

	def download_nginx_engine
		if @options[:brief]
			puts " --> Installing Nginx #{@options[:nginx_version]} engine"
		else
			puts "#{@colors.blue_bg}#{@colors.yellow}#{@colors.bold}" +
				"Downloading an Nginx #{@options[:nginx_version]} engine " +
				"for your platform#{@colors.reset}"
			puts
		end
		begin
			DownloadNginxEngineCommand.new(@options[:download_args]).run
			return true
		rescue SystemExit => e
			return e.success?
		end
	end

	def compile_nginx_engine(tmpdir)
		puts
		puts "---------------------------------------"
		puts
		puts "No precompiled Nginx engine could be downloaded. Compiling it from source instead."
		puts
		args = @options[:compile_args].dup
		args << "--working-dir"
		args << tmpdir
		CompileNginxEngineCommand.new(args).run
	end
end

end # module Config
end # module PhusionPassenger
