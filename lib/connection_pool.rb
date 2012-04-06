require 'rubygems'
require 'active_support/core_ext/module/synchronization'
require 'monitor'
require 'set'
require 'timeout'
# Generic connection pool class inspired from ActiveRecord ConnectionPool.
# Sharing a limited number of network connections among many threads.
# Connections are created delayed.
#
# == Introduction
#
# A connection pool synchronizes thread access to a limited number of
# network connections. The basic idea is that each thread checks out a
# database connection from the pool, uses that connection, and checks the
# connection back in. ConnectionPool is completely thread-safe, and will
# ensure that a connection cannot be used by two threads at the same time,
# as long as ConnectionPool's contract is correctly followed. It will also
# handle cases in which there are more threads than connections: if all
# connections have been checked out, and a thread tries to checkout a
# connection anyway, then ConnectionPool will wait until some other thread
# has checked in a connection.
#
# == Obtaining (checking out) a connection
#
# Connections can be obtained and used from a connection pool in several
# ways:
#
# 1. Use connection_pool.connection to obtain a connection instance.
#    and when you're done with the connection(s) and wish it to be returned
#    to the pool, you can call connection_pool.release_connection to release
#    connection back to the connection pool.
# 2. Manually check out a connection from the pool with connection_pool.checkout.
#    You are responsible for returning this connection to the pool when
#    finished by calling connection_pool.checkin(connection).
# 3. Use connection_pool.with_connection(&block), which obtains a connection,
#    yields it as the sole argument to the block, and returns it to the pool
#    after the block completes.
#
#    Connections in the pool may be Adapter instance that should implete methods like
#    verify!, disconnect!, active? etc.
#
# == Example
#
#   connection_pool = ConnectionPool.new(:size => 5, :timeout => 5) do
#     new_connection_adapter
#   end
#   connection_pool.connection
#   connection_pool.release_connection
#
#   connection = connection_pool.checkout
#   connection_pool.checkin(connection)
#
#   connection.with_connection{|connection| do_somting_with_connection}
#
#
#   Do something in the block, that always create an adapter instance or connect to a server.
#
class ConnectionPool
  VERSION = '0.1.0'

  class ConnectionTimeoutError < ::Timeout::Error
  end

  attr_reader :options

  DEFAULT_OPTIONS = { :size => 5, :timeout => 5 }



  # Creates a new ConnectionPool object. +spec+ is a ConnectionSpecification
  # object which describes database connection information (e.g. adapter,
  # host name, username, password, etc), as well as the maximum size for
  # this ConnectionPool.
  #
  # The default ConnectionPool maximum size is 5.
  def initialize(options = {}, &block)
    @options = DEFAULT_OPTIONS.merge(options)

    raise ArgumentError, "Connection pool requires a block that create a new connection!" unless block

    @connection_block = block

    # The cache of reserved connections mapped to threads
    @reserved_connections = {}

    # The mutex used to synchronize pool access
    @connection_mutex = Monitor.new
    @queue = @connection_mutex.new_cond

    # default 5 second timeout
    @timeout = @options[:timeout]

    # default max pool size to 5
    @size = @options[:size]

    @connections = []
    @checked_out = []
  end

  # Retrieve the connection associated with the current thread, or call
  # #checkout to obtain one if necessary.
  #
  # #connection can be called any number of times; the connection is
  # held in a hash keyed by the thread id.
  def connection
    @reserved_connections[current_connection_id] ||= checkout
  end

  # Signal that the thread is finished with the current connection.
  # #release_connection releases the connection-thread association
  # and returns the connection to the pool.
  def release_connection
    conn = @reserved_connections.delete(current_connection_id)
    checkin conn if conn
  end

  # If a connection already exists yield it to the block.  If no connection
  # exists checkout a connection, yield it to the block, and checkin the
  # connection when finished.
  def with_connection
    fresh_connection = true unless connection_cached?
    yield connection
  ensure
    release_connection if fresh_connection
  end

  # Returns true if a connection has already been opened.
  def connected?
    !@connections.empty?
  end

  # Disconnects all connections in the pool, and clears the pool.
  def disconnect!
    @reserved_connections.each do |name,conn|
      checkin conn
    end
    @reserved_connections = {}
    @connections.each do |conn|
      conn.disconnect!
    end
    @connections = []
  end

  # Verify active connections and remove and disconnect connections
  # associated with stale threads.
  def verify_active_connections! #:nodoc:
    clear_stale_cached_connections!
    @connections.each do |connection|
      connection.verify!
    end
  end

  # Return any checked-out connections back to the pool by threads that
  # are no longer alive.
  def clear_stale_cached_connections!
    keys = @reserved_connections.keys - Thread.list.find_all { |t|
      t.alive?
    }.map { |thread| thread.object_id }
    keys.each do |key|
      checkin @reserved_connections[key]
      @reserved_connections.delete(key)
    end
  end

  # Check-out a database connection from the pool, indicating that you want
  # to use it. You should call #checkin when you no longer need this.
  #
  # This is done by either returning an existing connection, or by creating
  # a new connection. If the maximum number of connections for this pool has
  # already been reached, but the pool is empty (i.e. they're all being used),
  # then this method will wait until a thread has checked in a connection.
  # The wait time is bounded however: if no connection can be checked out
  # within the timeout specified for this pool, then a ConnectionTimeoutError
  # exception will be raised.
  #
  # Returns: connection instance return by the connection_block
  #
  def checkout
    # Checkout an available connection
    @connection_mutex.synchronize do
      loop do
        conn = if @checked_out.size < @connections.size
                 checkout_existing_connection
               elsif @connections.size < @size
                 checkout_new_connection
               end
        return conn if conn
        # No connections available; wait for one
        if @queue.wait(@timeout)
          next
        else
          # try looting dead threads
          clear_stale_cached_connections!
          if @size == @checked_out.size
            raise ConnectionTimeoutError, "Could not obtain a connection within #{@timeout} seconds. The max pool size is currently #{@size}; consider increasing it."
          end
        end
      end
    end
  end

  # Check-in a connection back into the pool, indicating that you
  # no longer need this connection.
  #
  # +conn+: which was obtained by earlier by calling +checkout+ on this pool.
  def checkin(conn)
    @connection_mutex.synchronize do
      @checked_out.delete conn
      @queue.signal
    end
  end

  # whether connection cached in the current thread
  def connection_cached?
    !!@reserved_connections[current_connection_id]
  end

  synchronize :verify_active_connections!, :connected?, :disconnect!, :with => :@connection_mutex

  private
  def new_connection
    @connection_block.call
  end

  def current_connection_id #:nodoc:
    Thread.current.object_id
  end

  def checkout_new_connection
    c = new_connection
    @connections << c
    checkout_and_verify(c)
  end

  def checkout_existing_connection
    c = (@connections - @checked_out).first
    checkout_and_verify(c)
  end

  def checkout_and_verify(c)
    # connection must have verify! method that verify the connection active;
    # it should auto retry to reconnect if not active.
    c.verify!
    @checked_out << c
    c
  end
end
