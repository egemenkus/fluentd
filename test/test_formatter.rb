require_relative 'helper'
require 'fluent/test'
require 'fluent/formatter'

module FormatterTest
  include Fluent

  def tag
    'tag'
  end

  def record
    {'message' => 'awesome', 'greeting' => 'hello'}
  end

  def config_element_in_params(params)
    config_element('test', '', params)
  end

  class BaseFormatterTest < ::Test::Unit::TestCase
    include FormatterTest

    def test_call
      formatter = Formatter.new
      formatter.configure(config_element())
      assert_raise NotImplementedError do
        formatter.format('tag', Engine.now, {})
      end
    end
  end

  class BaseFormatterTestWithTestDriver < ::Test::Unit::TestCase
    include FormatterTest

    def create_driver(conf={})
      Fluent::Test::FormatterTestDriver.new(Formatter).configure(conf)
    end

    def test_call
      d = create_driver
      assert_raise NotImplementedError do
        d.format('tag', Engine.now, {})
      end
    end

    def test_call_with_string_literal_configure
      d = create_driver('')
      assert_raise NotImplementedError do
        d.format('tag', Engine.now, {})
      end
    end
  end

  class OutFileFormatterTest < ::Test::Unit::TestCase
    include FormatterTest

    def setup
      @formatter = Fluent::Test::FormatterTestDriver.new('out_file')
      @time = Engine.now
      @newline = if Fluent.windows?
                   "\r\n"
                 else
                   "\n"
                 end
    end

    def configure(conf)
      @formatter.configure({'utc' => true}.merge(conf))
    end

    def test_format
      configure({})
      formatted = @formatter.format(tag, @time, record)

      assert_equal("#{time2str(@time)}\t#{tag}\t#{Yajl.dump(record)}#{@newline}", formatted)
    end

    def test_format_without_time
      configure('output_time' => 'false')
      formatted = @formatter.format(tag, @time, record)

      assert_equal("#{tag}\t#{Yajl.dump(record)}#{@newline}", formatted)
    end

    def test_format_without_tag
      configure('output_tag' => 'false')
      formatted = @formatter.format(tag, @time, record)

      assert_equal("#{time2str(@time)}\t#{Yajl.dump(record)}#{@newline}", formatted)
    end

    def test_format_without_time_and_tag
      configure('output_tag' => 'false', 'output_time' => 'false')
      formatted = @formatter.format('tag', @time, record)

      assert_equal("#{Yajl.dump(record)}#{@newline}", formatted)
    end

    def test_format_without_time_and_tag_against_string_literal_configure
      @formatter.configure(%[
        utc         true
        output_tag  false
        output_time false
      ])
      formatted = @formatter.format('tag', @time, record)

      assert_equal("#{Yajl.dump(record)}#{@newline}", formatted)
    end
  end

  class JsonFormatterTest < ::Test::Unit::TestCase
    include FormatterTest

    def setup
      @formatter = Fluent::Test::FormatterTestDriver.new(TextFormatter::JSONFormatter)
      @time = Engine.now
      @newline = if Fluent.windows?
                   "\r\n"
                 else
                   "\n"
                 end
    end

    data('oj' => 'oj', 'yajl' => 'yajl')
    def test_format(data)
      @formatter.configure('json_parser' => data)
      formatted = @formatter.format(tag, @time, record)

      assert_equal("#{Yajl.dump(record)}#{@newline}", formatted)
    end
  end

  class MessagePackFormatterTest < ::Test::Unit::TestCase
    include FormatterTest

    def setup
      @formatter = TextFormatter::MessagePackFormatter.new
      @time = Engine.now
    end

    def test_format
      @formatter.configure(config_element())
      formatted = @formatter.format(tag, @time, record)

      assert_equal(record.to_msgpack, formatted)
    end
  end

  class LabeledTSVFormatterTest < ::Test::Unit::TestCase
    include FormatterTest

    def setup
      @formatter = TextFormatter::LabeledTSVFormatter.new
      @time = Engine.now
      @newline = if Fluent.windows?
                   "\r\n"
                 else
                   "\n"
                 end
    end

    def test_config_params
      assert_equal "\t", @formatter.delimiter
      assert_equal  ":", @formatter.label_delimiter

      @formatter.configure(config_element_in_params(
        'delimiter'       => ',',
        'label_delimiter' => '=',
      ))

      assert_equal ",", @formatter.delimiter
      assert_equal "=", @formatter.label_delimiter
    end

    def test_format
      @formatter.configure(config_element())
      formatted = @formatter.format(tag, @time, record)

      assert_equal("message:awesome\tgreeting:hello#{@newline}", formatted)
    end

    def test_format_with_customized_delimiters
      @formatter.configure(config_element_in_params(
        'delimiter'       => ',',
        'label_delimiter' => '=',
      ))
      formatted = @formatter.format(tag, @time, record)

      assert_equal("message=awesome,greeting=hello#{@newline}", formatted)
    end

    def record_with_tab
      {'message' => "awe\tsome", 'greeting' => "hello\t"}
    end

    def test_format_suppresses_tab
      @formatter.configure(config_element())
      formatted = @formatter.format(tag, @time, record_with_tab)

      assert_equal("message:awe some\tgreeting:hello #{@newline}", formatted)
    end

    def test_format_suppresses_tab_custom_replacement
      @formatter.configure(config_element_in_params(
        'replacement'      => 'X',
      ))
      formatted = @formatter.format(tag, @time, record_with_tab)

      assert_equal("message:aweXsome\tgreeting:helloX#{@newline}", formatted)
    end

    def test_format_suppresses_custom_delimiter
      @formatter.configure(config_element_in_params(
        'delimiter'       => 'w',
        'label_delimiter' => '=',
      ))
      formatted = @formatter.format(tag, @time, record)

      assert_equal("message=a esomewgreeting=hello#{@newline}", formatted)
    end
  end

  class CsvFormatterTest < ::Test::Unit::TestCase
    include FormatterTest

    def setup
      @formatter = TextFormatter::CsvFormatter.new
      @time = Engine.now
    end

    def test_config_params
      assert_equal ',', @formatter.delimiter
      assert_equal true, @formatter.force_quotes
      assert_nil @formatter.fields
    end

    data(
      'tab_char' => ["\t", '\t'],
      'tab_string' => ["\t", 'TAB'],
      'pipe' => ['|', '|'])
    def test_config_params_with_customized_delimiters(data)
      expected, target = data
      @formatter.configure(config_element_in_params('delimiter' => target, 'fields' => 'a,b,c'))
      assert_equal expected, @formatter.delimiter
      assert_equal ['a', 'b', 'c'], @formatter.fields
    end

    def test_format
      @formatter.configure(config_element_in_params('fields' => 'message,message2'))
      formatted = @formatter.format(tag, @time, {
        'message' => 'awesome',
        'message2' => 'awesome2'
      })
      assert_equal("\"awesome\",\"awesome2\"\n", formatted)
    end

    def test_format_with_customized_delimiters
      @formatter.configure(config_element_in_params(
        'fields' => 'message,message2',
        'delimiter' => '\t'
      ))
      formatted = @formatter.format(tag, @time, {
        'message' => 'awesome',
        'message2' => 'awesome2'
      })
      assert_equal("\"awesome\"\t\"awesome2\"\n", formatted)
    end

    def test_format_with_non_quote
      @formatter.configure(config_element_in_params(
        'fields' => 'message,message2',
        'force_quotes' => 'false'
      ))
      formatted = @formatter.format(tag, @time, {
        'message' => 'awesome',
        'message2' => 'awesome2'
      })
      assert_equal("awesome,awesome2\n", formatted)
    end

    data(
      'nil' => {
        'message' => 'awesome',
        'message2' => nil,
        'message3' => 'awesome3'
      },
      'blank' => {
        'message' => 'awesome',
        'message2' => '',
        'message3' => 'awesome3'
      })
    def test_format_with_empty_fields(data)
      @formatter.configure(config_element_in_params(
        'fields' => 'message,message2,message3'
      ))
      formatted = @formatter.format(tag, @time, data)
      assert_equal("\"awesome\",\"\",\"awesome3\"\n", formatted)
    end

    data(
      'normally' => 'one,two,three',
      'white_space' => 'one , two , three',
      'blank' => 'one,,two,three')
    def test_config_params_with_fields(data)
      @formatter.configure(config_element_in_params('fields' => data))
      assert_equal %w(one two three), @formatter.fields
    end
  end

  class SingleValueFormatterTest < ::Test::Unit::TestCase
    include FormatterTest
    def setup
      @newline = if Fluent.windows?
                   "\r\n"
                 else
                   "\n"
                 end
    end


    def test_config_params
      formatter = TextFormatter::SingleValueFormatter.new
      assert_equal "message", formatter.message_key

      formatter.configure(config_element_in_params('message_key' => 'foobar'))
      assert_equal "foobar", formatter.message_key
    end

    def test_format
      formatter = Fluent::Plugin.new_formatter('single_value')
      formatter.configure(config_element())
      formatted = formatter.format('tag', Engine.now, {'message' => 'awesome'})
      assert_equal("awesome#{@newline}", formatted)
    end

    def test_format_without_newline
      formatter = Fluent::Plugin.new_formatter('single_value')
      formatter.configure(config_element_in_params('add_newline' => 'false'))
      formatted = formatter.format('tag', Engine.now, {'message' => 'awesome'})
      assert_equal("awesome", formatted)
    end

    def test_format_with_message_key
      formatter = TextFormatter::SingleValueFormatter.new
      formatter.configure(config_element_in_params('message_key' => 'foobar'))
      formatted = formatter.format('tag', Engine.now, {'foobar' => 'foo'})

      assert_equal("foo#{@newline}", formatted)
    end
  end

  class FormatterLookupTest < ::Test::Unit::TestCase
    include FormatterTest

    def test_unknown_format
      assert_raise NotFoundPluginError do
        Fluent::Plugin.new_formatter('unknown')
      end
    end

    data('register_formatter' => 'known', 'register_template' => 'known_old')
    def test_find_formatter(data)
      $LOAD_PATH.unshift(File.join(File.expand_path(File.dirname(__FILE__)), 'scripts'))
      assert_nothing_raised ConfigError do
        Fluent::Plugin.new_formatter(data)
      end
      $LOAD_PATH.shift
    end
  end
end
