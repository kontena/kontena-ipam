describe EtcdClient do
  let :version do
    {"etcdserver"=>"2.3.3", "etcdcluster"=>"2.3.0"}
  end
  before do
    allow_any_instance_of(described_class).to receive(:api_execute).with('/version', :get).and_return(instance_double(Net::HTTPResponse,
      body: version.to_json,
    ))
  end

  context 'for the default configuration' do
    let :subject do
      described_class.new()
    end

    it 'initializes the configuration' do
      expect(subject.host).to eq 'localhost'
      expect(subject.port).to eq 2379
      expect(subject.use_ssl).to be false
    end

    it 'logs requests for a node' do
      response = instance_double(Net::HTTPResponse,
        body: '{"node": {"key": "/test", "value": "test"}}',
      )
      expect(response).to receive(:[]).with('X-Etcd-Index').and_return('4')
      expect(response).to receive(:[]).with('X-Raft-Index').and_return('3')
      expect(response).to receive(:[]).with('X-Raft-Term').and_return('2')

      response = Etcd::Response.from_http_response(response)

      expect(subject.log_response(:get, '/test', {}, response)).to eq "get /test {}: node@4: test"
    end

    it 'logs requests for a directory' do
      response = instance_double(Net::HTTPResponse,
        body: {'node' => { 'key' => "/test", 'dir' => true, 'nodes' => [
          { 'key' => "/test/bar", 'value' => 'bar' },
          { 'key' => "/test/foo", 'value' => 'foo' },
          { 'key' => "/test/subdir", 'dir' => true, 'nodes' => [ ] },
        ]}}.to_json,
      )
      expect(response).to receive(:[]).with('X-Etcd-Index').and_return('4')
      expect(response).to receive(:[]).with('X-Raft-Index').and_return('3')
      expect(response).to receive(:[]).with('X-Raft-Term').and_return('2')

      response = Etcd::Response.from_http_response(response)

      expect(subject.log_response(:get, '/test', {}, response)).to eq "get /test {}: directory@4: bar foo subdir/"
    end

    it 'logs errors' do
      response = instance_double(Net::HTTPResponse,
        body: {'errorCode' => 100, 'index' => 4, 'cause' => '/test', 'message' => "Key not found"}.to_json,
      )
      error = Etcd::Error.from_http_response(response)

      expect(subject.log_error(:get, '/test', {}, error)).to eq "get /test {}: error Etcd::KeyNotFound /test@4: Key not found"
    end
  end

  context 'with debug logging' do
    let :subject do
      described_class.new()
    end
    before do
      subject.logger.level = Logger::DEBUG
    end

    it 'logs get responses' do
      response = instance_double(Net::HTTPResponse,
        body: '{"node": {"key": "/test", "value": "test"}}',
      )
      expect(response).to receive(:[]).with('X-Etcd-Index').and_return('4')
      expect(response).to receive(:[]).with('X-Raft-Index').and_return('3')
      expect(response).to receive(:[]).with('X-Raft-Term').and_return('2')

      expect(subject).to receive(:api_execute).with('/v2/keys/test', :get, params: {}).and_return(response)
      expect(subject).to receive(:log_response).with(:get, '/test', {}, Etcd::Response)

      response = subject.get('/test')

      expect(response.etcd_index).to eq 4
      expect(response.node.key).to eq '/test'
      expect(response.node.value).to eq 'test'
    end

    it 'logs get errors' do
      response = instance_double(Net::HTTPResponse,
        body: {'errorCode' => 100, 'index' => 4, 'cause' => '/test', 'message' => "Key not found"}.to_json,
      )
      error = Etcd::Error.from_http_response(response)

      expect(subject).to receive(:api_execute).with('/v2/keys/test', :get, params: {}).and_raise(error)
      expect(subject).to receive(:log_error).with(:get, '/test', {}, error)

      expect{subject.get('/test')}.to raise_error(Etcd::KeyNotFound)
    end
  end

  context 'with info logging' do
    let :subject do
      described_class.new()
    end
    before do
      subject.logger.level = Logger::INFO
    end

    it 'does not log get responses' do
      response = instance_double(Net::HTTPResponse,
        body: '{"node": {"key": "/test", "value": "test"}}',
      )
      expect(response).to receive(:[]).with('X-Etcd-Index').and_return('4')
      expect(response).to receive(:[]).with('X-Raft-Index').and_return('3')
      expect(response).to receive(:[]).with('X-Raft-Term').and_return('2')

      expect(subject).to receive(:api_execute).with('/v2/keys/test', :get, params: {}).and_return(response)
      expect(subject).to_not receive(:log_response)

      response = subject.get('/test')

      expect(response.etcd_index).to eq 4
      expect(response.node.key).to eq '/test'
      expect(response.node.value).to eq 'test'
    end

    it 'does not log get errors' do
      response = instance_double(Net::HTTPResponse,
        body: {'errorCode' => 100, 'index' => 4, 'cause' => '/test', 'message' => "Key not found"}.to_json,
      )
      error = Etcd::Error.from_http_response(response)

      expect(subject).to receive(:api_execute).with('/v2/keys/test', :get, params: {}).and_raise(error)
      expect(subject).to_not receive(:log_error)

      expect{subject.get('/test')}.to raise_error(Etcd::KeyNotFound)
    end
  end

  context 'for the http://172.16.0.1:4001 endpoint' do
    let :subject do
      described_class.new('ETCD_ENDPOINT' => 'http://172.16.0.1:4001')
    end

    it 'initializes the configuration' do
      expect(subject.host).to eq '172.16.0.1'
      expect(subject.port).to eq 4001
      expect(subject.use_ssl).to be false
    end
  end

  context 'for an invalid endpoint' do
    it 'fails on an invalid URL' do
      expect{described_class.new('ETCD_ENDPOINT' => '172.16.0.1:4001')}.to raise_error(URI::InvalidURIError)
    end
  end
end
