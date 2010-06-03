#!/usr/local/bin/ruby
# -*- encoding:utf-8 -*-
require "nokogiri"
require "date"

class String
  def force_encode(encode)
    if RUBY_VERSION < '1.9.0'
      require 'kconv'
      toutf8
    else
      force_encoding(encode)
    end
  end
end

module YahooJPStock
  BASE_URLS = {
    :quote => "http://stocks.finance.yahoo.co.jp/stocks/detail/",
    :find  => "http://stocks.finance.yahoo.co.jp/stocks/search/",
    :history => "http://table.yahoo.co.jp/"
  }

  module Interface
    require "net/http"
    def get(uri)
      Net::HTTP.get_response(URI.parse(uri))
    rescue => e
      raise InterfaceError, "#{e.message}\n\n#{e.backtrace}"
    end
  end

  class Find
    include Interface
    def initialize(company_name)
      @company_name = URI.escape(company_name)
      @candidates = []
      uri = BASE_URLS[:find] + "?s=" + @company_name
      parse get(uri)
    end

    def parse(response)
      case response
      when Net::HTTPSuccess
        parsed_html = Nokogiri::HTML(response.body)
        @company_name = parsed_html.css('title').text.sub(/：.*/, '')
        parsed_html.css('div.boardFinList tr').each do |tr|
          @candidates << tr.search('td', 'th').inject([]) { |mem, item| mem << item.text; mem }
        end
        @candidates.map! do |ca|
          if ca.length > 8
            ca[5,2] = "#{ca[5]}(#{ca[6]})"
            ca[3,2] = "#{ca[4]}(#{ca[3]})"
          end
          ca[0..-2]
        end
      when Net::HTTPRedirection
        code = response['location'].match(/\?code=/).post_match
        q = Quote.new(code)
        2.times do |i|
          @candidates << [q.symbol[i], q.exchange[i], q.name[i], q.current_price[i], q.last_trade_price[i], q.volume[i]]
        end
        @candidates
      end
    rescue => e
      raise ParseError, "#{e.message}\n\n#{e.backtrace}"
    end

    def output
      @candidates
    end
  end
  
  class Quote
    include Interface
    SUMMARY = {
      :exchange => ['div.selectFin span.s170', 'div.selectFin option'],
      :current_price => ['div.priceDetail td.yjSt', 'div.priceDetail span.yjFL'],
      :day_change => ['div.priceDetail span.yjMSt', 'div.priceDetail p.yjSt']
    }
      
    DETAILS = [
      :last_trade_price, :open_price, :day_high, :day_low, :volume,
      :trade_amount, :day_range, :market_cap, :shares, :div_yield,
      :dividend, :per, :pbr, :eps, :bps, :minimum_cost, :minimum_shares,
      :year_high, :year_low, :outstand_margin_buy, :margin_buy_week_change,
      :oustand_margin_sell, :margin_sell_week_change
    ]

    (SUMMARY.keys + DETAILS).each { |k| attr_reader k }
    attr_reader :name, :symbol
  
    def initialize(stock_code)
      @symbol = ['コード', URI.escape(stock_code)]
      @name = ['名称', nil]
      uri = BASE_URLS[:quote] + "?code=" + @symbol[1]
      parse get(uri)
    end

    def parse(response)
      case response
      when Net::HTTPSuccess
        parsed_html = Nokogiri::HTML(response.body)
        @name[1], @symbol[1] = parsed_html.css('title').text.scan(/^(.+)【(\d+)】/).flatten
        SUMMARY.each do |k, (n, v)|
          title, value = 
            if name_value = parsed_html.at_css(n)
              name_value.text.sub(/\n.*/, '').split('：')
            else
              [k, nil]
            end
          value = parsed_html.at_css(v).text.sub(/\n/, '') if value.nil? and parsed_html.at_css(v)
          instance_variable_set("@#{k.to_s}", [title, value])
        end
        parsed_html.css('div.lineFi').each_with_index do |node, i|
          title  = node.search('dt').text.sub(/\n.*/, '')
          value = node.search('dd').text.gsub(/\n/, '')
          instance_variable_set("@#{DETAILS[i].to_s}", [title, value])
        end
      end
    rescue => e
      raise ParseError, "#{e.message}\n\n#{e.backtrace}"
    end

    def output(format=:to_hash)
      case format
      when :to_hash
        (SUMMARY.keys + DETAILS).inject({}) do |mem, meth|
          mem[meth] = send(meth)
          mem
        end.merge({:name => name, :symbol => symbol})
      when :to_array
        (SUMMARY.keys + DETAILS).inject([]) do |mem, meth|
          mem += [send(meth)] if send(meth)
          mem
        end.unshift(name, symbol).transpose
      end
    end
  end

  class History
    include Interface
    def initialize(stock_code, start_date, end_date, term=:daily) #term= :daily, :weekly, :monthly
      @symbol = URI.escape(stock_code)
      st = start_date.respond_to?(:year) ? start_date : Date.parse(start_date)
      en = end_date.respond_to?(:year) ? end_date : Date.parse(end_date)
      term = term.to_s[/\w/]
      uri = BASE_URLS[:history] + "t?" + "c=#{st.year}&a=#{st.mon}&b=#{st.day}" +
                                         "&f=#{en.year}&d=#{en.mon}&e=#{en.day}" +
                                         "&g=#{term}&s=#{@symbol}&y=0&z=#{@symbol}&x=sb"
      @histories = []
      parse get(uri)
    end

    def parse(response)
      case response
      when Net::HTTPSuccess
        parsed_html = Nokogiri::HTML(response.body.force_encode('EUC-JP'))
        parsed_html.css("table > tr").each do |tr|
          bg = tr.attributes['bgcolor']
          next unless bg && ["#eeeeee", "#ffffff"].include?(bg.value)
          @histories << 
            tr.search('td small', 'th small').inject([]) { |mem, item| mem << item.text; mem }
        end
      end
    rescue => e
      raise ParseError, "#{e.message}\n\n#{e.backtrace}"
    end

    def output
      @histories
    end
  end
end

if __FILE__ == $0
  p YahooJPStock::Quote.new('998405').output(:to_array)
  #p YahooJPStock::Find.new('toyota').output
  #p YahooJPStock::History.new('7203', '2010/1/10', '2010/2/10').output
end
