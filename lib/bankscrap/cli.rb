require 'thor'
require 'active_support/core_ext/string'
Dir[File.expand_path("../../..", __FILE__) + "/generators/*.rb"].each do |generator|
  require generator
end


module Bankscrap
  class CLI < Thor
    def self.shared_options
      option :credentials, default: {}, type: :hash
      option :log,         default: false
      option :debug,       default: false
      option :iban,        default: nil
      option :format
      option :output
    end

    desc 'balance BankName', "get accounts' balance"
    shared_options
    def balance(bank)
      assign_shared_options
      initialize_client_for(bank)

      @client.accounts.each do |account|
        say "Account: #{account.description} (#{account.iban})", :cyan
        say "Balance: #{account.balance}", :green
      end
    end

    desc 'transactions BankName', "get account's transactions"
    shared_options
    options from: :string, to: :string
    def transactions(bank)
      assign_shared_options

      start_date = parse_date(options[:from]) if options[:from]
      end_date = parse_date(options[:to]) if options[:to]

      initialize_client_for(bank)

      account = @iban ? @client.account_with_iban(@iban) : @client.accounts.first

      if start_date && end_date
        if start_date > end_date
          say 'From date must be lower than to date', :red
          exit
        end

        transactions = account.fetch_transactions(start_date: start_date, end_date: end_date)
      else
        transactions = account.transactions
      end

      export_to_file(transactions, options[:format], options[:output]) if options[:format]

      say "Transactions for: #{account.description} (#{account.iban})", :cyan
      transactions.each do |transaction|
        say transaction.to_s, (transaction.amount > Money.new(0) ? :green : :red)
      end
    end


    register(Bankscrap::AdapterGenerator, "generate_adapter", "generate_adapter MyBankName", 
      "generates a template for a new Bankscrap bank adapter")

    private

    def assign_shared_options
      @credentials  = options[:credentials]
      @iban         = options[:iban]
      @log          = options[:log]
      @debug        = options[:debug]
    end

    def initialize_client_for(bank_name)
      bank_class = find_bank_class_for(bank_name)
      Bankscrap.log = @log
      Bankscrap.debug = @debug
      @client = bank_class.new(@credentials)
    end

    def find_bank_class_for(bank_name)
      require "bankscrap-#{bank_name.underscore.dasherize}"
      Object.const_get("Bankscrap::#{bank_name}::Bank")
    rescue LoadError
      raise ArgumentError.new('Invalid bank name.')
    rescue NameError
      raise ArgumentError.new("Invalid bank name. Did you mean \"#{bank_name.upcase}\"?")
    end

    def parse_date(string)
      Date.strptime(string, '%d-%m-%Y')
    rescue ArgumentError
      say 'Invalid date format. Correct format d-m-Y (eg: 31-12-2016)', :red
      exit
    end

    def export_to_file(data, format, path)
      exporter(format, path).write_to_file(data)
    end

    def exporter(format, path)
      case format.downcase
      when 'csv' then BankScrap::Exporter::Csv.new(path)
      else
        say 'Sorry, file format not supported.', :red
        exit
      end
    end
  end
end
