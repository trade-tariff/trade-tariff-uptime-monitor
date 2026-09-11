# frozen_string_literal: true

RSpec.describe 'pagerduty lambda' do
  subject(:pagerduty) { load_lambda('lambda/pagerduty/lambda_function.rb') }

  let(:sns_event) do
    {
      'Records' => [
        {
          'Sns' => {
            'Message' => {
              'AlarmName' => 'uptime-find-commodity-production',
              'AlarmDescription' => 'Uptime check failed for find-commodity',
              'NewStateValue' => 'ALARM',
              'NewStateReason' => 'Threshold Crossed'
            }.to_json
          }
        }
      ]
    }
  end

  after { ENV.delete('PAGERDUTY_ROUTING_KEY') }

  describe '#lambda_handler' do
    it 'raises when the routing key is unset, so the invocation fails visibly' do
      ENV.delete('PAGERDUTY_ROUTING_KEY')

      expect { pagerduty.lambda_handler(event: sns_event, context: nil) }
        .to raise_error(/PAGERDUTY_ROUTING_KEY/)
    end

    it 'raises when the routing key is empty' do
      ENV['PAGERDUTY_ROUTING_KEY'] = ''

      expect { pagerduty.lambda_handler(event: sns_event, context: nil) }
        .to raise_error(/PAGERDUTY_ROUTING_KEY/)
    end

    it 'raises when the routing key is only whitespace' do
      ENV['PAGERDUTY_ROUTING_KEY'] = '   '

      expect { pagerduty.lambda_handler(event: sns_event, context: nil) }
        .to raise_error(/PAGERDUTY_ROUTING_KEY/)
    end

    it 'triggers a PagerDuty event when the routing key is set' do
      ENV['PAGERDUTY_ROUTING_KEY'] = 'a-routing-key'
      request = stub_request(:post, 'https://events.pagerduty.com/v2/enqueue')
                .with(body: hash_including('routing_key' => 'a-routing-key', 'event_action' => 'trigger'))
                .to_return(status: 202, body: '{"status":"success"}')

      pagerduty.lambda_handler(event: sns_event, context: nil)

      expect(request).to have_been_requested
    end

    it 'resolves the PagerDuty event when the alarm returns to OK' do
      ENV['PAGERDUTY_ROUTING_KEY'] = 'a-routing-key'
      sns_event['Records'][0]['Sns']['Message'] =
        JSON.parse(sns_event['Records'][0]['Sns']['Message']).merge('NewStateValue' => 'OK').to_json
      request = stub_request(:post, 'https://events.pagerduty.com/v2/enqueue')
                .with(body: hash_including('event_action' => 'resolve'))
                .to_return(status: 202, body: '{"status":"success"}')

      pagerduty.lambda_handler(event: sns_event, context: nil)

      expect(request).to have_been_requested
    end
  end
end
