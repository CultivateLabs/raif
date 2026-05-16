# frozen_string_literal: true

# == Schema Information
#
# Table name: documents
#
#  id         :bigint           not null, primary key
#  content    :text
#  title      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Document < ApplicationRecord
end
