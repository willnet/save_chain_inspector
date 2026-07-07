# frozen_string_literal: true

require 'active_record'
require 'sqlite3'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')

ActiveRecord::Schema.define do
  create_table :posts, force: true
  create_table :comments, force: true do |t|
    t.bigint :post_id
  end
  create_table :callback_option_records, force: true
end

class Post < ActiveRecord::Base
  has_many :comments

  before_validation :prepare_post
  before_save :normalize_post
  before_save :skipped_post_callback, if: -> { false }
  after_create :notify_created

  def prepare_post; end

  def normalize_post; end

  def skipped_post_callback; end

  def notify_created; end
end

class Comment < ActiveRecord::Base
  belongs_to :post

  before_save :normalize_comment

  def normalize_comment; end
end

class CallbackOptionRecord < ActiveRecord::Base
  class << self
    def events
      @events ||= []
    end
  end

  before_validation :create_only_validation, on: :create
  before_save :prepended_save, prepend: true
  before_save :appended_save
  around_save :around_save_callback

  def create_only_validation
    self.class.events << :create_only_validation
  end

  def prepended_save
    self.class.events << :prepended_save
  end

  def appended_save
    self.class.events << :appended_save
  end

  def around_save_callback
    self.class.events << :around_before
    yield
    self.class.events << :around_after
  end
end
