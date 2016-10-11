describe RetryHelper do
  before do
    @total_sleep = 0.0

    allow(subject).to receive(:retry_sleep) { |t| @total_sleep += t }
  end

  context "using the default options" do
    it "returns immediately from yield on success" do
      expect(RetryHelper.with_retry(){ "foo" }).to eq "foo"
    end

    it "raises immediately from yield without exceptions given" do
      expect { RetryHelper.with_retry(){ fail "fail" } }.to raise_error(RuntimeError, "fail")
    end

    it "raises immediately from yield with other errors" do
      expect { RetryHelper.with_retry(ArgumentError){ fail "fail" } }.to raise_error(RuntimeError, "fail")
    end


    it "returns after multiple attempts" do
      count = 0

      expect(RetryHelper.with_retry(ArgumentError){
        count += 1
        if count < 3
          raise ArgumentError
        else
          count
        end
      }).to eq 3

      expect(@total_sleep).to eq 1.0 + 2.0
    end

    it "raises after too many attempts" do
      count = 0

      expect{ RetryHelper.with_retry(RuntimeError){
        count += 1

        fail
      } }.to raise_error(RuntimeError)

      expect(count).to eq 5
      expect(@total_sleep).to eq 1.0 + 2.0 + 3.0 + 4.0 + 5.0
    end

  end
end
