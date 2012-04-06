require File.expand_path("../", __FILE__) + '/spec_helper'

def mock_connection_adapter
  mock_connection_adapter = mock("connection_adapter")
  mock_connection_adapter.stub!(:verify!)
  mock_connection_adapter.stub!(:active?)
  mock_connection_adapter.stub!(:disconnect!)
  mock_connection_adapter
end

describe ConnectionPool do
  describe "initialize ConnectionPool" do
    it "raise ArgumentError if block not given" do
      lambda{ConnectionPool.new}.should raise_error(ArgumentError)
    end
    it "connection pool size default 5, and can customize" do
      ConnectionPool.new{}.options[:size].should == 5
      ConnectionPool.new(:size => 10){}.options[:size].should == 10
    end
    it "connection timeout default 5, and can customize" do
      ConnectionPool.new{}.options[:timeout].should == 5
      ConnectionPool.new(:timeout => 10){}.options[:timeout].should == 10
    end
  end

  describe "#connection" do
    before do
      @connection_pool = ConnectionPool.new{mock_connection_adapter}
    end
    it "should return a connection from connection pool" do
      @connection_pool.connection.should_not be_nil
    end
    it "should cache the connection when call the #connection method and repeat call multi times should return the same connection if in the same thread" do
      @connection_pool.connection.should == @connection_pool.connection
      @connection_pool.should be_connection_cached
    end
    it "in different threads should return different connection when call #connection method" do
      main_thread_connection = @connection_pool.connection
      Thread.new{@connection_pool.connection.should_not == main_thread_connection}
    end
  end

  describe "#release_connection" do
    before do
      @connection_pool = ConnectionPool.new{mock_connection_adapter}
    end
    it "should delete the cached connection" do
      @connection_pool.connection
      @connection_pool.release_connection
      @connection_pool.should_not be_connection_cached
    end
    it "should check in the connection back to the connection pool" do
      @connection_pool.connection
      @connection_pool.release_connection
      @connection_pool.instance_variable_get("@checked_out").should be_empty
    end
  end

  describe "#checkout " do
    before do
      @connection_pool = ConnectionPool.new{mock_connection_adapter}
      @exist_connections = []
      5.times do
        Thread.new{con = @connection_pool.checkout; @exist_connections << con}
      end
      @exist_connections.each{|con|@connection_pool.checkin(con)}
    end
    it "should checkout the exist connection if connections not empty" do
      con = @connection_pool.checkout
      @exist_connections.should include(con)
    end
    it "should raise error if can not obtain a connection for timeout" do
      threads = []
      5.times do
        threads << Thread.new{@connection_pool.checkout; sleep(5)}
      end
      lambda{@connection_pool.checkout}.should raise_error(ConnectionPool::ConnectionTimeoutError)
      threads.each(&:join)
    end
  end

  describe "#with_connection" do
    before do
      @connection_pool = ConnectionPool.new{mock_connection_adapter}
    end
    it "should check in the connection back to the pool if it is a fresh connection" do
      @connection_pool.with_connection{|connection|}
      @connection_pool.should_not be_connection_cached
      @connection_pool.instance_variable_get("@checked_out").should be_empty
    end
    it "should not check in the connection back to the pool if it is a cached connection" do
      @connection_pool.connection
      @connection_pool.with_connection{|connection|}
      @connection_pool.should be_connection_cached
      @connection_pool.instance_variable_get("@checked_out").should_not be_empty
    end
  end
end
