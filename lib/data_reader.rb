require 'yaml'
require 'csv'

module HashNesting

  def nest
    result = {}.extend HashNesting
    primaryKeys.each { |key| traverse_nest( "#{key}", self[key] ) { |k,v| result[k] = v } }
    result
  end

  def nest!
    keys = primaryKeys
    tmp = self.dup
    self.keys.each { |k| self.delete k}
    keys.each { |key| traverse_nest( "#{key}", tmp[key] ) { |k,v| self[k] = v} }
    self
  end

  def unnest
    result = {}.extend HashNesting
    for key in primaryKeys
      true_keys = key.to_s.split('.')
      resolve_nesting( result, self[key], *true_keys)
    end
    result
  end

  def unnest!
    for key in primaryKeys
      true_keys = key.to_s.split('.')
      value = self[key]
      self.delete key
      resolve_nesting( self, value, *true_keys)
    end
    self
  end

  private

  # if hash has both string and symbol keys, symbol wins
  def primaryKeys
    sym_keys = []
    str_keys = []
    self.keys.each { |k|
      case k
      when Symbol
        sym_keys << k
      when String
        str_keys << k
      else
        str_keys << k
      end
    }
    str_keys.delete_if {|k| sym_keys.member? k.to_s.to_sym }
    sym_keys + str_keys
  end

  def resolve_nesting( dest, data, *keys )
    return data if keys.empty?
    dest ||= {}
    key = keys.shift.to_sym
    if keys.first.to_i.to_s == keys.first
      # array
      index = keys.shift.to_i - 1
      raise "illegal index: #{keys.join '.'}  index must be >= 1" if index < 0
      dest[key] ||= []
      dest[key][index] = resolve_nesting( dest[key][index], data, *keys )
    else
      # hash
      dest[key] = resolve_nesting( dest[key], data, *keys )
    end
    dest
  end

  def traverse_nest( namespace, data, &block )
    case data.class.to_s
    when 'Array'
      data.each_with_index { |v,i| traverse_nest( "#{namespace}.#{i+1}", v, &block ) }
    when 'Hash'
      data.each { |k,v| traverse_nest( "#{namespace}.#{k}", v, &block ) }
    else
      yield namespace, data.to_s
    end
  end

end # HashNesting

# DataReader is a class for loading in data files.  It is used to support bulk file-based operations.
# DataReader supports a number of different formats:
# * YAML
# * Tabular
# * CSV
# * Java Properties
# By default, DataReader assumes Tabular, but load and save both support your choice of format
class DataReader

  attr_accessor :data

  def initialize(data=[])
    @data = data
  end

  def [](index)
    return @data[index]
  end

  def []=(index)
    return @data[index]
  end

  def hashonkeys_load( filename, keys, format=:CSV )
    return {} unless File.exists?(filename)
    raw_data = File.read(filename)
    case format
    when :CSV
      data = CSV.parse(raw_data)
      header = data[0].map { |col| col.to_sym }

      keys_indices = []
      keys.each do |k|
        index = header.index(k)
        if index
          keys_indices << index
        else
          raise "key #{k} not found in csv header"
        end
      end

      # Construct hash with array keys and hash values
      @data = {}
      data[1..-1].each do |row|
        key = keys_indices.map { |k| row[k] }
        value = {}
        header.each_with_index do |col, i|
          value[col] = row[i]
        end
        @data[key] = value
      end
      # README array keys are strings. Hashes keyed by symbol.
      return @data
    else
      raise "invalid format. options are :CSV"
    end
  end

  def load( filename, format=:CSV )
    return {} unless File.exists? filename
    raw_data = File.read( filename )
    case format
    when :Tabular
      @data = parse_csv( raw_data, "\t" )
    when :YAML
      @data = YAML.load( raw_data ) || {}
    when :CSV
      @data = parse_csv( raw_data )
    when :Properties
      @data = parse_properties( raw_data )
    else
      raise "invalid format. options are :Tabular, :YAML, :CSV, :Properties"
    end
  end

  def save( filename, format=:CSV, force_headers=false )
    return if @data.nil? or @data.empty?
    existing = File.exists?( filename ) && File.size( filename ) > 0
    File.open( filename, 'a+' ) {|f|
      f << case format
      when :Tabular
        generate_csv( @data, force_headers || !existing, "\t" )
      when :YAML
        YAML.dump( @data )
      when :CSV
        generate_csv( @data, force_headers || !existing )
      when :Properties
        generate_properties( @data )
      end
      f << "\n" # adding a newline on the end, so appending is happy
    }
  end

  def self.hashonkeys_load( filename, keys, format=:CSV )
    reader = DataReader.new()
    reader.hashonkeys_load( filename, keys, format )
  end


  def self.load( filename, format=:CSV )
    reader = DataReader.new()
    reader.load( filename, format )
  end

  def self.save( filename, data, format=:CSV, force_headers=false )
    reader = DataReader.new( data )
    reader.save( filename, format, force_headers )
  end

  private

  def parse_csv( raw_data, delim=nil )
    rows = CSV.parse( raw_data, delim )
    return parse_rows( rows )
  end

  def parse_rows( rows )
    processed = []
    headers = rows.shift
    for row in rows
      item = {}
      headers.each_index do |i|
        item[headers[i].to_sym] = correct_type(row[i]) unless row[i].nil? or row[i].empty?
      end
      item.extend HashNesting
      processed << item.unnest
    end
    return processed
  end

  def split_data( data )
    data = data.collect {|d| d.extend(HashNesting).nest }
    headers = data[0].keys.sort
    rows = data.collect { |item|
      row = []
      item.keys.each {|k|
        headers << k unless headers.include? k
        index = headers.index k
        row[index] = item[k].to_s
      }
      row
    }
    return headers, rows
  end

  def generate_csv( data, dump_header, delim=nil )
    return "" if data.nil? or data.empty?
    headers, rows = split_data( data )
    return generate_rows( headers, rows, dump_header, delim )
  end

  def generate_rows( headers, rows, dump_header, record_seperator=nil )
    rows.unshift headers if dump_header
    buff = rows.collect { |row|
      CSV.generate_line( row, record_seperator )
    }
    return buff.join("\n")
  end

  def parse_properties( raw_data )
    processed = {}
    for line in raw_data.split(/\n\r?/)
      next if line =~ /^\W*(#.*)?$/ # ignore lines beginning w/ comments
      if md = /^([^:=]+)[=:](.*)/.match(line)
        processed[md[1].strip] = correct_type(md[2].strip)
      end
    end
    processed.extend HashNesting
    return processed.unnest
  end

  def generate_properties( raw_data )
    raw_data.extend HashNesting
    (raw_data.nest.collect {|k,v| "#{k}:#{v}" }).join("\n")
  end

  # convert to integer if possible
  def correct_type( str )
    return str.to_f if str =~ /^\d+\.\d+$/ unless str =~ /^0\d/
    return str.to_i if str =~ /^\d+$/ unless str =~ /^0\d/
    return str
  end

end # DataReader
