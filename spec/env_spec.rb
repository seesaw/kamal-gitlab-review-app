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
end
