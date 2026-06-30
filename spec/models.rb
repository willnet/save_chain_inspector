# frozen_string_literal: true

require 'active_record'
require 'sqlite3'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')

ActiveRecord::Schema.define do
  create_table :posts, force: true
  create_table :comments, force: true do |t|
    t.bigint :post_id
  end
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
