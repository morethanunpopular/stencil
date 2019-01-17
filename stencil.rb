#!/usr/bin/ruby
require 'logger'
require 'json'
require  'erb'
require  'tilt'
require "net/http"
require "uri"
require 'digest'
require 'open3'

# Define global Logger var
$logger = Logger.new(STDOUT)

class Stencil
  # The Stencil class represents and instance of Stencil which will poll consul for updates
  # and generate new files based on the defined templates
  attr_reader :options

  def initialize(options)
    # Stencil.initialize accepts a hash of config options, and returns an instance of the Stencil class
    # The options hash must define a templates config file path and the url for the consul host to use
    @options = options
    template_hashes = self.parseTemplates
    templates = []
    template_hashes.each do | hash |
      hash['consul_host'] = options['consul_host']
      template = Template.new(hash)
      templates.push(template)
    end
    options['templates'] = templates
  end

  def parseTemplates
    # The Stencil.parseTemplates function accepts no arguments, parses the config file specified in self.options
    # And returns a list of templates to be managed
    $logger.info('Parsing Config file...')
    fh = File.open(options['config_file'])
    data = fh.read
    fh.close
    templates = JSON.parse(data)['templates']
    return templates
  end  

  def main
    # The Stencil.main function accepts no arguments, and starts a daemonized loop for checking the status of
    # The services specified in the template config files and re-templating config files on state change of the service
    while true
      options['templates'].each do | template |
        hosts, has_changed = template.fetchUpdates
        if has_changed 
          $logger.info('Generating Template for ' + template.options['target'] + "...")
          template.renderTemplate(hosts)
          template.executeCallback
        end
      end
      sleep(2)
    end
  end
end

class Template
  # The templace class represents a defined template in the config file
  attr_reader :options
  attr_reader :last_digest

  def initialize(options)
    # Template.initialize accepts a hash representing the meta data about a given template
    # And returns an instance of a Template object
    @options = options
    @last_digest = nil
  end

  def fetchUpdates
    # Template.fetchUpdate queries the consul host for the health status of a given service
    # And then checks if this has changed. If it has, it regenerates the specified template
    url = self.options['consul_host'] + '/v1/health/service/' + self.options['service']
    $logger.debug("Consul Service Check: " + url)
    uri = URI(url)
#    params = {"passing" => 1}
#    uri.query = URI.encode_www_form(params)
    hosts = {
      'passing' => [],
      'failing' => []
    }
    Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') do |http|
      request = Net::HTTP::Get.new(uri.request_uri)
      @digest = Digest::MD5.hexdigest http.request(request).body
      data = JSON.parse(http.request(request).body) 
      data.each do |node|
        passing = true
        node['Checks'].each do | check |
          if check['Status'] != 'passing' && check['ServiceName'] == self.options['service']
            passing = false
          end
        end
        node_hash = {
          'name' => node['Node']['Node'],
          'address' => node['Node']['Address'],
          'port'  => node['Service']['Port']
        }
        if passing
          hosts['passing'].push(node_hash)
        else
          hosts['failing'].push(node_hash)
        end
      end
    end
    if self.last_digest != @digest
      $logger.debug("Digest has changed!")
      has_changed = true
      @last_digest = @digest
    else
     $logger.debug("No Status Change for " + self.options['service'])
      has_changed = false 
    end
    return hosts, has_changed
  end

  def fetchParams
    return {}
  end
 
  def renderTemplate(hosts)
    # Template.renderTemplate accepts a list of healthy hosts for a given service as arguments, and then
    # Renders the updated config file and writes it to the target path
    params = self.fetchParams
    puts hosts
    params['hosts'] = hosts
    erb = Tilt::ERBTemplate.new(options['template'])
    output = erb.render(self, params)
    File.write(options['target'], output)
    $logger.info('New template written for ' + self.options['target'] + "!") 
  end

  def executeCallback
    command = self.options['callback']['command']
    $logger.info('Executing Callback: ' + command)
    Open3.popen3(command) do | stdin, stdout, stderr, thread |
      lines = stdout.read.split("\n")
      lines.each do | line |
        $logger.debug('Callback Output: ' + line)
      end
      $logger.info('Callback: ' + thread.value.to_s)
    end 
  end
end

def main
  # The main functions parses basic config from the environment,
  # instantiates the main Stencil object, and starts the daemonized process

  if ENV.key?("TEMPLATES_FILE") && ENV.key?("CONSUL_HOST")    
    templates_file = ENV['TEMPLATES_FILE']
    consul_host = ENV['CONSUL_HOST']
  else
    $logger.error('No Config in Environment!')
    exit!
  end
  begin
    $logger.info("Starting Stencil Daemon...")
    stencil = Stencil.new({
       "config_file" => templates_file,
       "consul_host" => consul_host
    })
    stencil.main
  rescue
    $logger.error($!)
    exit!
  end
end

# Run main function
main
