#!/usr/bin/env ruby

class Registrator
  require 'json'
  require 'csv'
  require "yaml"
  require 'open-uri'
  require 'mail'
  require 'erb'
  require 'pp'

  CONFIG_FILE = 'config.yml'
  DATASTORE_FILE = 'datastore.json'

  def initialize
    # load configuration
    @config = load_configuration

    # init variables from persistent datastore
    @users = datastore_load

    # load registered users
    load_registered

    # save datastore
    datastore_save

    # load payments
    load_payments

    # save datastore
    datastore_save

    # send emails 
    send_emails

    # save datastore
    datastore_save
  end

  private

  # prepends current path
  def cur_dir(file)
    File.dirname(__FILE__) + '/' + file
  end

  # load configuration
  def load_configuration
    if File.file?(cur_dir(CONFIG_FILE))
      YAML.load_file(cur_dir(CONFIG_FILE))
    else
      raise "config file (#{cur_dir(CONFIG_FILE)}) is missing"
    end
  end

  # 
  # default objects
  #

  # default user helper
  def default_user(id, payment_id)
    user = {
      "id" => id,
      "notifications" =>
        {
        "registration" => nil,
        "payment" => nil,
        "payment_reminder" => nil
        },
      "created_at" => DateTime.now,
      "payment_id" => payment_id,
      "payment_at" => nil
    }

    # raise exception if user is not complete
    raise "user record invalid (#{user.inspect})" if user['id'].nil? || user['payment_id'].nil?

    return user
  end

  # 
  # sending emails
  #

  def send_emails
    puts @users.inspect
    Array(@users).each do |key, user|
      puts user.inspect

      if user['notifications']['registration'].nil?
        # send registration mail
        mailer('registration', user)
      elsif user['notifications']['payment'].nil? and !user['payment_at'].nil?
        # send payment_confirmation
        mailer('payment', user)
      elsif user['payment_at'].nil? && user['notifications']['payment_reminder'].nil? && (DateTime.now - DateTime.parse(user['created_at'])).to_f >= @config['reminder_days']
        # payment reminder 
        mailer('payment_reminder', user)
      end

    end
  end

  def mailer(type, user)
    # default e-mail settings
    sender = @config['email_sender']

    case type
    when 'registration'
      subject = 'UZEL: Potvrzení o přijetí přihlášky a pokyny k platbě'
      body =
        ERB.new(File.read(cur_dir('templates/registration.erb'))).result(binding) +
        ERB.new(File.read(cur_dir('templates/footer.erb'))).result(binding)
    when 'payment'
      subject = 'UZEL: Potvrzení o zaplacení'
      body =
        ERB.new(File.read(cur_dir('templates/payment.erb'))).result(binding) +
        ERB.new(File.read(cur_dir('templates/footer.erb'))).result(binding)
    when 'payment_reminder'
      subject = 'UZEL: Připomenutí platby za akci'
      body =
        ERB.new(File.read(cur_dir('templates/payment_reminder.erb'))).result(binding) +
        ERB.new(File.read(cur_dir('templates/footer.erb'))).result(binding)
    else
      raise "unknown mailer (#{type})"
    end

    # create Mail object
    if defined?(subject) && defined?(body) && !subject.nil? && !body.nil?
      mail = Mail.new do
        from    sender
        to      user['id']
        subject subject
        body    body
        delivery_method :sendmail
      end

      # wait some tome before sending an e-mail
      sleep_time = 5 + Random.rand(5)
      puts "will send #{type} to #{user['id']} in #{sleep_time} sec ..."
      sleep(sleep_time)

      pp mail
      puts mail.body

      # send email
      user['notifications'][type] = DateTime.now if mail.deliver!
    end
  end

  #
  # datastore saving & loading
  #

  # load from DATASTORE_PATH file
  def datastore_load
    if File.file?(cur_dir(DATASTORE_FILE))
      YAML.load_file(cur_dir(DATASTORE_FILE))
    else
      {}
    end
  end

  # save to DATASTORE_PATH file
  def datastore_save
    #File.write(DATASTORE_PATH, @users.to_json) 
    File.write(cur_dir(DATASTORE_FILE), @users.to_yaml)
  end

  # load registered users
  def load_registered
    ## read file from @config['registerd_url']
    datafile = open(@config['registered_url']).read()

    ## change encoding
    datafile.force_encoding 'utf-8'
    datafile.valid_encoding?

    # parse retrieved csv file
    CSV.parse(datafile, headers: true, encoding: 'iso-8859-1:utf-8').each do |row|
      add_user(
        row[@config['field']],
        row[@config['field_payid']]
      ) unless row[@config['field']].nil? or row[@config['field_payid']].nil?
    end
  end

  # add user to datastore
  def add_user(id, payid)
    @users[id] = default_user(id, payid) unless @users.include?(id)
  end

  #
  # payments
  #

  # load payments from FIO bank
  def load_payments
    period_begin = @config['period_begin']
    period_end = Time.now.strftime('%F')
    amount_required = @config['amount_required']

    # construct URL
    url = "https://www.fio.cz/ib_api/rest/periods/#{@config['token']}/#{period_begin}/#{period_end}/transactions.json"
    puts url

    transactions = {}

    #open(url) do |f|
    #  file = f.read
    #  parsed = JSON.parse(file)

    #  # loop transactions and save to var
    #  unless parsed['accountStatement']['transactionList'].nil?
    #    parsed['accountStatement']['transactionList']['transaction'].each do |item|
    #      vs = item['column5']['value'].to_s unless item['column5'].nil?
    #      unless vs.nil?
    #        transactions[vs] = {
    #          amount: item['column1']['value'],
    #          comment: item['column25'].nil? ? nil : item['column25']['value']
    #        }
    #      end
    #    end
    #  end

    #  pp transactions

    #  # loop people with payment == nil
    #  @users.each do |key, user|
    #    if user['payment_at'].nil? and !user['payment_id'].nil?
    #      # will try to find payment
    #      puts "looking payment with VS #{user['payment_id']}"
    #      puts transactions[user['payment_id']]
    #      if !transactions[user['payment_id']].nil? && transactions[user['payment_id']][:amount] == amount_required
    #        puts "uživatel zaplatil"
    #        user['payment_at'] = DateTime.now
    #      end
    #    end
    #  end

    #end

  end
end

# run registrator
Registrator.new
