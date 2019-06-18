# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), "dependencies"))

class JenkinsJobCreateFromTemplateV1

  def initialize(input)
    # Set the input document attribute
    @input_document = REXML::Document.new(input)

    # Retrieve all of the handler info values and store them in a hash variable named @info_values.
    @info_values = {}
    REXML::XPath.each(@input_document, "/handler/infos/info") do |item|
      @info_values[item.attributes["name"]] = item.text.to_s.strip
    end

    # Retrieve all of the handler parameters and store them in a hash variable named @parameters.
    @parameters = {}
    REXML::XPath.each(@input_document, "/handler/parameters/parameter") do |item|
      @parameters[item.attributes["name"]] = item.text.to_s.strip
    end

    @enable_debug_logging = @info_values['enable_debug_logging'].downcase == 'yes' ||
                            @info_values['enable_debug_logging'].downcase == 'true'
    puts "Parameters: #{@parameters.inspect}" if @enable_debug_logging
  end

  def execute
    resource = RestClient::Resource.new("#{@info_values['jenkins_location']}",
      :user => @info_values['username'], :password => @info_values['password'])

    puts "Retrieve the config.xml for the template project '#{@parameters['template_job']}'" if @enable_debug_logging
    begin
      config_xml = resource["job/#{URI.escape(@parameters['template_job'])}/config.xml"].get
    rescue RestClient::Exception => e
      puts "#{e.http_code}: #{e.http_body}"
      raise "#{e.http_code} #{RestClient::STATUSES[e.http_code]}"
    end

    puts "Successfully retrieved the config.xml for the template job. Attempting to make the template substitutions." if @enable_debug_logging
    begin
      json_subs = JSON.parse(@parameters['template_substitutions'])
    rescue Exception => e
      raise e,"Template Substitutions JSON can't be parsed: #{e.message}."
    end

    json_subs.each do |k,v|
      puts "Substituting '#{k}' for '#{v}'" if @enable_debug_logging
      config_xml.gsub!(k,escape(v))
    end

    puts "Substitutions completed." if @enable_debug_logging

    puts "Attempting to retrieve the Jenkins crumb (needed to properly authenticate POST request)." if @enable_debug_logging
    crumb_xml = resource['crumbIssuer/api/xml'].get
    crumb = /<crumb>(.*?)<\/crumb>/.match(crumb_xml)[1]

    puts "Crumb retrieved. Creating job with the results config.xml" if @enable_debug_logging
    RestClient.log = "stdout"
    begin
      response = resource["createItem?name=#{URI.escape(@parameters['name'])}"].post(config_xml,
        :content_type => "text/xml",:"Jenkins-Crumb" => crumb)
    rescue RestClient::Exception => e
      puts "#{e.http_code}: #{e.http_body}"
      raise "#{e.http_code} #{RestClient::STATUSES[e.http_code]}"
    end
    puts response
    puts "Job successfully created" if @enable_debug_logging

    return <<-RESULTS
    <results>
      <result name="Job URL">#{escape(@info_values['jenkins_location'].chomp("/")+"/project/"+URI.escape(@parameters['name']))}</result>
    </results>
    RESULTS
  end

  ##############################################################################
  # General handler utility functions
  ##############################################################################
  # This is a template method that is used to escape results values (returned in
  # execute) that would cause the XML to be invalid.  This method is not
  # necessary if values do not contain character that have special meaning in
  # XML (&, ", <, and >), however it is a good practice to use it for all return
  # variable results in case the value could include one of those characters in
  # the future.  This method can be copied and reused between handlers.
  def escape(string)
      # Globally replace characters based on the ESCAPE_CHARACTERS constant
      string.to_s.gsub(/[&"><]/) { |special| ESCAPE_CHARACTERS[special] } if string
  end
  # This is a ruby constant that is used by the escape method
  ESCAPE_CHARACTERS = {'&'=>'&amp;', '>'=>'&gt;', '<'=>'&lt;', '"' => '&quot;'}
end