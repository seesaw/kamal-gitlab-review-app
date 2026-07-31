# frozen_string_literal: true

RSpec.describe KamalGitlabReviewApp::Env do
  include_context 'with review app env'

  it 'defaults accessories to db' do
    expect(described_class.accessories).to eq(%w[db])
  end

  it 'parses CSV accessories' do
    ENV['REVIEW_ACCESSORIES'] = 'db, redis'
    expect(described_class.accessories).to eq(%w[db redis])
  end

  it 'treats empty and none as no accessories' do
    ENV['REVIEW_ACCESSORIES'] = ''
    expect(described_class.accessories).to eq([])
    ENV['REVIEW_ACCESSORIES'] = 'none'
    expect(described_class.accessories).to eq([])
  end

  it 'resolves db_accessory from REVIEW_DB_ACCESSORY or the first accessory' do
    expect(described_class.db_accessory).to eq('db')

    ENV['REVIEW_ACCESSORIES'] = 'postgres,redis'
    expect(described_class.db_accessory).to eq('postgres')

    ENV['REVIEW_DB_ACCESSORY'] = 'redis'
    expect(described_class.db_accessory).to eq('redis')
  ensure
    ENV.delete('REVIEW_DB_ACCESSORY')
  end

  it 'returns nil db_accessory when accessories are disabled' do
    ENV['REVIEW_ACCESSORIES'] = 'none'
    expect(described_class.db_accessory).to be_nil
  end
end
