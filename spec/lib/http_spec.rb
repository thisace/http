require "json"

require "support/dummy_server"
require "support/proxy_server"

RSpec.describe HTTP do
  run_server(:dummy) { DummyServer.new }
  run_server(:dummy_ssl) { DummyServer.new(:ssl => true) }

  let(:ssl_client) do
    HTTP::Client.new :ssl_context => SSLHelper.client_context
  end

  context "getting resources" do
    it "is easy" do
      response = HTTP.get dummy.endpoint
      expect(response.to_s).to match(/<!doctype html>/)
    end

    context "with URI instance" do
      it "is easy" do
        response = HTTP.get HTTP::URI.parse dummy.endpoint
        expect(response.to_s).to match(/<!doctype html>/)
      end
    end

    context "with query string parameters" do
      it "is easy" do
        response = HTTP.get "#{dummy.endpoint}/params", :params => {:foo => "bar"}
        expect(response.to_s).to match(/Params!/)
      end
    end

    context "with query string parameters in the URI and opts hash" do
      it "includes both" do
        response = HTTP.get "#{dummy.endpoint}/multiple-params?foo=bar", :params => {:baz => "quux"}
        expect(response.to_s).to match(/More Params!/)
      end
    end

    context "with headers" do
      it "is easy" do
        response = HTTP.accept("application/json").get dummy.endpoint
        expect(response.to_s.include?("json")).to be true
      end
    end
  end

  describe ".via" do
    context "anonymous proxy" do
      run_server(:proxy) { ProxyServer.new }

      it "proxies the request" do
        response = HTTP.via(proxy.addr, proxy.port).get dummy.endpoint
        expect(response.headers["X-Proxied"]).to eq "true"
      end

      it "responds with the endpoint's body" do
        response = HTTP.via(proxy.addr, proxy.port).get dummy.endpoint
        expect(response.to_s).to match(/<!doctype html>/)
      end

      it "raises an argument error if no port given" do
        expect { HTTP.via(proxy.addr) }.to raise_error HTTP::RequestError
      end

      it "ignores credentials" do
        response = HTTP.via(proxy.addr, proxy.port, "username", "password").get dummy.endpoint
        expect(response.to_s).to match(/<!doctype html>/)
      end

      context "ssl" do
        it "responds with the endpoint's body" do
          response = ssl_client.via(proxy.addr, proxy.port).get dummy_ssl.endpoint
          expect(response.to_s).to match(/<!doctype html>/)
        end

        it "ignores credentials" do
          response = ssl_client.via(proxy.addr, proxy.port, "username", "password").get dummy_ssl.endpoint
          expect(response.to_s).to match(/<!doctype html>/)
        end
      end
    end

    context "proxy with authentication" do
      run_server(:proxy) { AuthProxyServer.new }

      it "proxies the request" do
        response = HTTP.via(proxy.addr, proxy.port, "username", "password").get dummy.endpoint
        expect(response.headers["X-Proxied"]).to eq "true"
      end

      it "responds with the endpoint's body" do
        response = HTTP.via(proxy.addr, proxy.port, "username", "password").get dummy.endpoint
        expect(response.to_s).to match(/<!doctype html>/)
      end

      it "responds with 407 when wrong credentials given" do
        response = HTTP.via(proxy.addr, proxy.port, "user", "pass").get dummy.endpoint
        expect(response.status).to eq(407)
      end

      it "responds with 407 if no credentials given" do
        response = HTTP.via(proxy.addr, proxy.port).get dummy.endpoint
        expect(response.status).to eq(407)
      end

      context "ssl" do
        it "responds with the endpoint's body" do
          response = ssl_client.via(proxy.addr, proxy.port, "username", "password").get dummy_ssl.endpoint
          expect(response.to_s).to match(/<!doctype html>/)
        end

        it "responds with 407 when wrong credentials given" do
          response = ssl_client.via(proxy.addr, proxy.port, "user", "pass").get dummy_ssl.endpoint
          expect(response.status).to eq(407)
        end

        it "responds with 407 if no credentials given" do
          response = ssl_client.via(proxy.addr, proxy.port).get dummy_ssl.endpoint
          expect(response.status).to eq(407)
        end
      end
    end
  end

  context "posting forms to resources" do
    it "is easy" do
      response = HTTP.post "#{dummy.endpoint}/form", :form => {:example => "testing-form"}
      expect(response.to_s).to eq("passed :)")
    end
  end

  context "posting with an explicit body" do
    it "is easy" do
      response = HTTP.post "#{dummy.endpoint}/body", :body => "testing-body"
      expect(response.to_s).to eq("passed :)")
    end
  end

  context "with redirects" do
    it "is easy for 301" do
      response = HTTP.follow.get("#{dummy.endpoint}/redirect-301")
      expect(response.to_s).to match(/<!doctype html>/)
    end

    it "is easy for 302" do
      response = HTTP.follow.get("#{dummy.endpoint}/redirect-302")
      expect(response.to_s).to match(/<!doctype html>/)
    end
  end

  context "head requests" do
    it "is easy" do
      response = HTTP.head dummy.endpoint
      expect(response.status).to eq(200)
      expect(response["content-type"]).to match(/html/)
    end
  end

  describe ".auth" do
    it "sets Authorization header to the given value" do
      client = HTTP.auth "abc"
      expect(client.default_headers[:authorization]).to eq "abc"
    end

    it "accepts any #to_s object" do
      client = HTTP.auth double :to_s => "abc"
      expect(client.default_headers[:authorization]).to eq "abc"
    end
  end

  describe ".basic_auth" do
    it "fails when options is not a Hash" do
      expect { HTTP.basic_auth "[FOOBAR]" }.to raise_error
    end

    it "fails when :pass is not given" do
      expect { HTTP.basic_auth :user => "[USER]" }.to raise_error
    end

    it "fails when :user is not given" do
      expect { HTTP.basic_auth :pass => "[PASS]" }.to raise_error
    end

    it "sets Authorization header with proper BasicAuth value" do
      client = HTTP.basic_auth :user => "foo", :pass => "bar"
      expect(client.default_headers[:authorization]).
        to match(%r{^Basic [A-Za-z0-9+/]+=*$})
    end
  end

  describe ".cache" do
    it "sets cache option" do
      cache = double(:cache, :perform => nil)
      client = HTTP.cache cache
      expect(client.default_options[:cache]).to eq cache
    end
  end

  describe ".persistent" do
    let(:host) { "https://api.github.com" }

    context "with host only given" do
      subject { HTTP.persistent host }
      it { is_expected.to be_an HTTP::Client }
      it { is_expected.to be_persistent }
    end

    context "with host and block given" do
      it "returns last evaluation of last expression" do
        expect(HTTP.persistent(host) { :http }).to be :http
      end

      it "auto-closes connection" do
        HTTP.persistent host do |client|
          expect(client).to receive(:close).and_call_original
          client.get("/repos/httprb/http.rb")
        end
      end
    end
  end

  describe ".timeout" do
    context "without timeout type" do
      subject(:client) { HTTP.timeout :read => 123 }

      it "sets timeout_class to PerOperation" do
        expect(client.default_options.timeout_class)
          .to be HTTP::Timeout::PerOperation
      end

      it "sets given timeout options" do
        expect(client.default_options.timeout_options)
          .to eq :read_timeout => 123
      end
    end

    context "with :null type" do
      subject(:client) { HTTP.timeout :null, :read => 123 }

      it "sets timeout_class to Null" do
        expect(client.default_options.timeout_class)
          .to be HTTP::Timeout::Null
      end
    end

    context "with :per_operation type" do
      subject(:client) { HTTP.timeout :per_operation, :read => 123 }

      it "sets timeout_class to PerOperation" do
        expect(client.default_options.timeout_class)
          .to be HTTP::Timeout::PerOperation
      end

      it "sets given timeout options" do
        expect(client.default_options.timeout_options)
          .to eq :read_timeout => 123
      end
    end

    context "with :global type" do
      subject(:client) { HTTP.timeout :global, :read => 123 }

      it "sets timeout_class to Global" do
        expect(client.default_options.timeout_class)
          .to be HTTP::Timeout::Global
      end

      it "sets given timeout options" do
        expect(client.default_options.timeout_options)
          .to eq :read_timeout => 123
      end
    end

    it "fails with unknown timeout type" do
      expect { HTTP.timeout(:foobar, :read => 123) }
        .to raise_error(ArgumentError, /foobar/)
    end
  end
end
