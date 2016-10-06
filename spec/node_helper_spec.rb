describe NodeHelper do

  class Test
    include NodeHelper

  end

  describe '#node' do

    it 'returns node from env if present' do
      expect(ENV).to receive(:[]).with('NODE_ID').and_return('foo')

      expect(Test.new.node).to eq('foo')
    end

    it 'returns node from hostname' do
      expect(ENV).to receive(:[]).with('NODE_ID').and_return(nil)
      expect(Socket).to receive(:gethostname).and_return('bar')

      expect(Test.new.node).to eq('bar')
    end
  end

end
