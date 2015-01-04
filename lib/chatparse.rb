require 'yaml'
require 'treetop'
require './mor'
require './chat'
require 'optparse'
require 'ostruct'

MOR_PARSER = MorParser.new
CHAT_PARSER = ChatParser.new

# Metadata for a CHAT Utterance that also contains information about the
# entire file.
class UtteranceMetadata
  attr_accessor :encoding, :participants, :languages, :situation, :warnings,
                :date, :comments, :birth, :location

  def initialize(metadata)
    @encoding = ''
    @participants = {}
    @languages = []
    @situation = ''
    @warnings = []
    @date = ''
    @comments = []
    @birth = {}
    @location = ''

    metadata.each do |field|
      field.gsub!(/[\t]/, ' ')
      case field
      when /^@UTF8/ then
        @encoding = 'utf8'
      when /^@Begin/ then
      when /^@Languages:/ then
        @languages = field.gsub(/^@Languages:/, '').strip
      when /^@Participants:/ then
        participants = field.gsub(/^@Participants:/, '').split(',').map(&:strip)
        participants.each do |p|
          code, name, description = p.split.map(&:strip)
          @participants[code] = {
            Code: code, Name: name, Description: description
          }
        end
      when /^@ID:/ then
        language, corpus, code, age, sex, group, ses, role, education =
          field.gsub(/^@ID:/, '').split('|').map(&:strip)
        @participants[code] = {} if @participants[code].nil?
        @participants[code].merge!(Language: language,
                                   Corpus: corpus,
                                   Age: age,
                                   Sex: sex,
                                   Group: group,
                                   SES: ses,
                                   Role: role,
                                   Education: education)
      when /^@Media:/ then # TODO: is this skipping?
      when /^@Situation:/ then
        @situation = field.gsub(/^@Situation:/, '').strip
      when /^@Warning:/ then
        @warnings = @warnings.push(field.gsub(/^@Warning:/, '').strip)
      when /^@Date:/ then
        @situation = field.gsub(/^@Situation:/, '').strip
      when /^@Comment:/ then
        @comments = @comments.push(field.gsub(/^@Comment:/, '').strip)
      when /^@Tape Location:/ then
      when /^@G:/ then
      when /^@Birth of (...):/ then
        @birth[$1] = field.gsub(/^@Birth of (...):/, '').strip
      when /^@Time Start:/ then
      when /^@Location:/ then
        @location = field.gsub(/^@Location:/, '').strip
      when /^@Activities:/ then
      when /^@Time Duration:/ then
      when /^@Bg:/ then
      when /^@Bg/ then
      when /^@Eg:/ then
      when /^@Eg/ then
      when /^@New Episode/ then
      when /^@Transcriber:/ then
      when /^@Room Layout:/ then
      when /^@Color words:/ then
      when /^@Bck:/ then
      # Added by Jesse
      when /^@PID:/ then
      when /^@Font:/ then  # Not needed, only in Brown/Eve
      else fail "Unknown metadata field: #{field}" end
    end
  end

  def to_a
    a = []
    # Hash of instance variables
    vars = Hash[instance_variables.map { |n| [n, instance_variable_get(n)] }]
    vars.each do |k, v|
      # FIXME: do we just leave symbol keys alone?
      a.push(k => v)
    end
  end
end

def symbols_to_strings(hash)
  # Convert a possibly nested hash's keys to strings if not already.
  # Done here because I'm not sure if extending Hash is bad practice.
  return hash.to_s if !hash.is_a?(Hash) || hash.is_a?(Array)
  hash.each_with_object({}) { |(k, v), h| h[k.to_s] = symbols_to_strings(v) }
end

def get_MOR_token_form(word_group)
  (word_group.map do |w|
    case
    when w[:Type] == :Punctuation then w[:Value]
    when w[:Type] == :PreClitic then w[:Word][:Stem]
    when w[:Type] == :Word then w[:Stem]
    when w[:Type] == :PostClitic then w[:Word][:Stem]
    when w[:Type] == :Compound then (w[:Parts].map { |p| p[:Stem] }).join('+')
    else fail "Can't handle this form!" end
  end).join('-')
end

def get_MOR_token_category(word_group)
  # puts word_group.inspect
  (word_group.map do |w|
    # puts w.inspect
    case
    when w[:Type] == :Punctuation then 'Punct'
    when w[:Type] == :PreClitic then w[:Word][:Pos][:Category]
    when w[:Type] == :Word then w[:Pos][:Category]
    when w[:Type] == :PostClitic then w[:Word][:Pos][:Category]
    when w[:Type] == :Compound then
      (w[:Parts].map { |p| p[:Pos][:Category] }).join('+')
    else fail "Can't handle this form!" end
  end).join('-')
end

def get_MOR_token_subcategory(word_group)
  # puts word_group.inspect
  (word_group.map do |w|
    # puts w.inspect
    case
    when w[:Type] == :Punctuation then 'Punct'
    when w[:Type] == :PreClitic then w[:Word][:Pos][:SubCategories].join('|')
    when w[:Type] == :Word then w[:Pos][:SubCategories].join('|')
    when w[:Type] == :PostClitic then w[:Word][:Pos][:SubCategories].join('|')
    when w[:Type] == :Compound then
      (w[:Parts].map { |p| p[:Pos][:SubCategories].join('|') }).join('+')
    else fail "Can't handle this form!" end
  end).join('-')
end

def get_MOR_token_subcategory(word_group)
  # puts word_group.inspect
  (word_group.map do |w|
    # puts w.inspect
    case
    when w[:Type] == :Punctuation then 'Punct'
    when w[:Type] == :PreClitic then w[:Word][:Pos][:SubCategories].join('|')
    when w[:Type] == :Word then w[:Pos][:SubCategories].join('|')
    when w[:Type] == :PostClitic then w[:Word][:Pos][:SubCategories].join('|')
    when w[:Type] == :Compound then
      (w[:Parts].map { |p| p[:Pos][:SubCategories].join('|') }).join('+')
    else fail "Can't handle this form!" end
  end).join('-')
end

def get_MOR_token_fusionalsuffixes(word_group)
  # puts word_group.inspect
  (word_group.map do |w|
    # puts w.inspect
    case
    when w[:Type] == :Punctuation then 'Punct'
    when w[:Type] == :PreClitic then
      w[:Word][:FusionalSuffixes].join('|') if w[:Word][:FusionalSuffixes]
    when w[:Type] == :Word then
      w[:FusionalSuffixes].join('|') if w[:FusionalSuffixes]
    when w[:Type] == :PostClitic then
      w[:Word][:FusionalSuffixes].join('|') if w[:FusionalSuffixes]
    when w[:Type] == :Compound then
      (w[:Parts].map do |p|
        p[:FusionalSuffixes].join('|') if w[:FusionalSuffixes]
      end).join('+')
    else fail "Can't handle this form!" end
  end).join('-')
end

def get_MOR_token_suffixes(word_group)
  # puts word_group.inspect
  (word_group.map do |w|
    # puts w.inspect
    case
    when w[:Type] == :Punctuation then 'Punct'
    when w[:Type] == :PreClitic then
      w[:Word][:Suffixes].join('|') if w[:Word][:Suffixes]
    when w[:Type] == :Word then
      w[:Suffixes].join('|') if w[:Suffixes]
    when w[:Type] == :PostClitic then
      w[:Word][:Suffixes].join('|') if w[:Word][:Suffixes]
    when w[:Type] == :Compound then
      (w[:Parts].map do |p|
        p[:Suffixes].join('|') if w[:Suffixes]
      end).join('+')
    else fail "Can't handle this form!" end
  end).join('-')
end

# Base Utterance class, including instance attributes such
# as the raw utterance, tokenized forms, parsed morphologies, and more.
class Utterance
  attr_accessor :num, :raw_utterance, :tokenized, :file_info, :speaker,
                :utterance_tokens, :annotations, :metadata, :corpus_metadata,
                :utterance_xml, :cleaned_utterance, :utterance_tokens, :age,
                :age_bin

  def initialize(num, utterance, filename, metadata)
    # corpusMetadata/@corpus_metadata param/variable omitted.
    # file_info -> filename
    @tokenized = nil
    @num = num
    @filename = filename
    # Make metadata object from Array
    @metadata = UtteranceMetadata.new(Array.new(metadata))
    # This is the metadata attached to the corpus file in parent directory

    tokens = utterance.first.split.map(&:strip)

    @speaker = tokens[0].gsub(/[*:]/, '').strip
    # Get everything but first row.
    # We have to make a number of fixes to the raw data to get parsing to work
    @raw_utterance = tokens.slice(1..-1).join(' ').gsub(/[^ ],/, ' ,')

    # Parse chat format
    p = CHAT_PARSER.parse(@raw_utterance)
    if p.nil?
      $stderr.puts "!!!!Can't CHAT Parse: #{@raw_utterance}"
    else
      @tokenized = p.replace.gsub(
        / ta /, ' to ' # Basic replacements
      ).gsub(
        /mhm/, 'yes'
      ).split.map(&:strip)
    end

    @annotations = Hash.new nil
    annotations = Array.new(utterance.slice(1..-1))
    # TODO: Figure out type of annotations
    annotations.each do |tier|
      case tier
      when /^%mor:/ # Morphemic segments by type and PoS
        # gets rid of tab and %mor
        morph = tier.gsub(/%(.*?):\t/, '').strip

        parse = MOR_PARSER.parse(morph)
        if parse.nil? || parse == []
          $stderr.puts "Can't MOR parse: #{annotations}"
        else
          @annotations[:mor] = parse.struct.map(&:first)
        end

        if @tokenized && @annotations[:mor]
          if @tokenized.length != @annotations[:mor].length
            # Immediate FIXME: This shuld not result in a nil tokenization,
            # need to distinguish between false alarms and real issues
            # $stderr.puts "Tokenization and morphology don't match:"
            # $stderr.puts "\t#{@raw_utterance}"
            # $stderr.puts "\t#{@tokenized.join(' ')}"
            # $stderr.puts "\t#{morph}"

            @annotations[:mor] = nil
          else
            @tokenized.length.times do |i|
              f = get_MOR_token_form(@annotations[:mor][i])
              next if f != @tokenized[i]
              # This happens when stem is different from token
              # $stderr.puts "Token and MOR don't match:"
              # $stderr.puts "\t#{@tokenized[i]}, #{f}"
            end
          end
        else
          fail "Nil tokenization: #{@raw_utterance}"
        end
      when /^%xgra:/ # More advanced GRA feature (not sure what though)
        # NOTE: This is syntax. It might be important to have that noted
        # somewhere else (previously it was with the :Syntax key)
        @annotations[:xgra] = tier.gsub(/%(.*?):\t/, '').split.map(&:strip)
      when /^%(.{3,4}):/ # All other annotations are treated the same
        # This is to_sym since everything else is!
        @annotations[$1.to_sym] = tier.gsub(/%(.*?):\t/, '')
      else fail "Unknown Tier: #{tier}"
      end
    end
  end

  def to_s
    %W(
      Utterance: #{@utterance.inspect}
      File: #{@file.inspect}
      MetaData: #{@metadata.inspect}
      Corpus: #{@corpus.inspect}
    )
  end

  def to_h
    # Convert to a hash for data serialization
    {
      speaker: @speaker,
      raw: @raw_utterance,
      tokenized: @tokenized,
      annotations: @annotations,
      num: @num
    }
  end
end # end childes utterance class

def parse_file(filename)
  # Parses a single file specified in corpus-file-info.rb
  # corpus_metadata omitted. Not sure what to do about the file_info hash.
  # Maybe an additional optional "metadata" file?

  # Get filename from file_info hash
  puts "Parsing file #{filename}"
  lines = File.readlines(filename)

  # grab the file fields
  fields = []
  last_field = ''
  lines.each do |line|
    case line
    # previously @, \*, and % were all separate fields, but that seems
    # unecessary since the code is the same, so I joined them
    when /^@/, # UTF8, @PID:, @Date, @Media (basically metadata)
         /^\*/, # *CHI, *LOI, TODO find out
         /^%/ # %mor, %gra, %act TODO find out
      fields = fields.push(last_field) unless last_field == ''
      last_field = line
    when /^\t/ then # Some lines are tabbed in, line continuation
      # This just makes sure line continuations are good to go
      last_field += line
    else fail "Don't know how to handle line: #{line}" end
  end

  utt_num = 0
  utterances = []
  metadata = []
  last_utterance = []

  fields.each do |field|
    # Get rid of line break
    field.gsub!(/[\n]/, ' ')
    case field
    when /^@/ then # @PID, @Comment, etc - add to metadata file
      metadata = metadata.push(field) unless field == ''
    when /^\*/ then # These are Utterances *CHI, *PAT, etc
      unless last_utterance == []
        # corpus_metadata param omitted, file_info hash -> filename
        utterances.push(Utterance.new(utt_num += 1,
                                      last_utterance,
                                      filename,
                                      metadata))
      end
      # Initialize our last utterance - so * marks beginning of utterances
      last_utterance = [field]
    when /^%/ then # Add to our last_utterance Array
      last_utterance = last_utterance.push(field)
    else fail "Don't know how to handle field: #{field}" end
  end

  utterances
end

def utterances_to_yaml(utterances)
  # Set up metadata
  yaml = {
    metadata: utterances[0].metadata.to_a,
    utterances: utterances.collect(&:to_h)
  }
  YAML.dump(yaml)
end

def yaml_to_chat(raw)
  puts raw[:Metadata]
end

options = {}

optparser = OptionParser.new do |opts|
  opts.banner = 'Usage: chatparse.rb [options] file'

  opts.separator ''
  opts.separator 'Specific options:'

  # TODO: Option for supplying metadata file

  options[:reverse] = false
  opts.on('-r', '--reverse', 'Convert YAML to CHAT') do
    options[:reverse] = true
  end

  opts.separator ''
  opts.separator 'Common options:'

  opts.on_tail('-h', '--help', 'Show this message') do
    puts opts
    exit
  end

  opts.on_tail('-v', '--version', 'Show version') do
    puts '0.0.0'
    exit
  end
end

if ARGV.empty?
  puts 'Usage: chatparse.rb [options] file'
  exit(-1)
end

optparser.parse!

ARGV.each do |f|
  if options[:reverse]
    raw = YAML.load_file(f)
    puts yaml_to_chat(raw)
  else
    utterances = parse_file(f)
    yaml = utterances_to_yaml(utterances)

    if f.end_with?('.cha')
      new = f.gsub('.cha', '.yaml')
    else
      new = "#{f}.yaml"
    end
    File.open(new, 'w') do |fout|
      fout.write(yaml)
    end

  end
end
