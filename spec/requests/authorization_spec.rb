require 'rails_helper'

RSpec.describe 'Authorization', type: :request do
  let(:tradeline) { create(:tradeline, amount: 1000) }
  let(:deposit) { create(:deposit, tradeline: tradeline) }

  endpoints = {
    'list tradelines' => ->(t, _d) { [:get, '/tradelines'] },
    'show tradeline' => ->(t, _d) { [:get, "/tradelines/#{t.id}"] },
    'create tradeline' => ->(_t, _d) { [:post, '/tradelines', { name: 'New', amount: '10.00' }] },
    'list deposits' => ->(t, _d) { [:get, "/tradelines/#{t.id}/deposits"] },
    'show deposit' => ->(t, d) { [:get, "/tradelines/#{t.id}/deposits/#{d.id}"] },
    'create deposit' => ->(t, _d) { [:post, "/tradelines/#{t.id}/deposits", { amount: '1.00', deposit_date: '2026-12-01' }] },
    'list audit events' => ->(_t, _d) { [:get, '/audit_events'] }
  }

  allowed = {
    viewer: ['list tradelines', 'show tradeline', 'list deposits', 'show deposit'],
    operator: ['list tradelines', 'show tradeline', 'list deposits', 'show deposit', 'create deposit'],
    admin: endpoints.keys
  }

  allowed.each do |role, permitted|
    context "as #{role}" do
      endpoints.each do |name, endpoint|
        if permitted.include?(name)
          it "can #{name}" do
            verb, path, body = endpoint.call(tradeline, deposit)
            send(verb, path, params: body&.to_json, headers: json_headers(role))
            expect(response).to have_http_status(:success)
          end
        else
          it "cannot #{name}" do
            verb, path, body = endpoint.call(tradeline, deposit)
            send(verb, path, params: body&.to_json, headers: json_headers(role))
            expect(response).to have_http_status(:forbidden)
            expect(json).to eq('error' => { 'code' => 'forbidden',
                                            'message' => 'This API key is not allowed to perform this action' })
          end
        end
      end
    end
  end

  it 'audits denied attempts with the actor' do
    post "/tradelines/#{tradeline.id}/deposits", params: { amount: 1, deposit_date: '2026-12-01' }.to_json,
                                                 headers: json_headers(:viewer)

    event = AuditEvent.find_by!(action: 'authorization.denied')
    expect(event.api_key.role).to eq('viewer')
    expect(event.metadata).to include('permission' => 'create_deposit', 'method' => 'POST',
                                      'path' => "/tradelines/#{tradeline.id}/deposits")
  end

  it 'does not create anything when denied' do
    expect do
      post "/tradelines/#{tradeline.id}/deposits", params: { amount: 1, deposit_date: '2026-12-01' }.to_json,
                                                   headers: json_headers(:viewer)
    end.not_to change(Deposit, :count)
  end

  it 'checks permissions before revealing whether a tradeline exists' do
    post '/tradelines/0/deposits', params: { amount: 1, deposit_date: '2026-12-01' }.to_json,
                                   headers: json_headers(:viewer)
    expect(response).to have_http_status(:forbidden)
  end
end
