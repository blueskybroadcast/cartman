module Cartman
  class Cart
    CART_LINE_ITEM_ID_KEY = "cartman:line_item:id"

    def initialize(uid)
      @uid = uid
    end

    def any_coupons?
      items.each { |item| return true unless item.value(:coupon_id).blank? }
      false
    end

    def apply_coupon?(coupon_id, coupon_code, product_id, product_type, discount)
      item = find_item_by_product product_id, product_type
      return false unless item
      return false if item.coupon_id == coupon_id
      item.coupon_id = coupon_id
      item.coupon_code = coupon_code
      item.discount = discount
    end

    def remove_coupon?(product_id, product_type)
      item = find_item_by_product product_id, product_type
      return false unless item
      item.coupon_id = nil
      item.coupon_code = nil
      item.discount = nil
      true
    end

    def find_item_by_product(product_id, product_type)
      items.each do |item|
        return item if item.id.to_i == product_id.to_i && item.type.downcase == product_type.downcase
      end
      nil
    end

    def add_item(options)
      raise "Must specify both :id and :type" unless options.has_key?(:id) && options.has_key?(:type)
      line_item_id = redis.incr CART_LINE_ITEM_ID_KEY
      redis.pipelined do
        redis.mapped_hmset("cartman:line_item:#{line_item_id}", options)
        redis.hincrby("cartman:line_item:#{line_item_id}", :_version, 1)
        redis.sadd key, line_item_id
        redis.sadd index_key, "#{options[:type]}:#{options[:id]}"
        redis.set index_key_for(options), line_item_id
      end
      touch
      get_item(line_item_id)
    end

    def remove_item(item)
      redis.del "cartman:line_item:#{item._id}"
      redis.srem key, item._id
      redis.srem index_key, "#{item.type}:#{item.id}"
      redis.del index_key_for(item)
      touch
    end

    def items(type=nil)
      if type
        items = line_item_ids.collect{ |item_id| get_item(item_id)}.select{ |item| item.type == type }
        return ItemCollection.new(items)
      else
        return ItemCollection.new(line_item_ids.collect{ |item_id| get_item(item_id)})
      end
    end

    def contains?(object)
      redis.sismember index_key, "#{object.class}:#{object.id}"
    end

    def find(object)
      if contains?(object)
        get_item(redis.get(index_key_for(object)).to_i)
      end
    end

    def count
      redis.scard key
    end

    def quantity
      line_item_keys.collect { |item_key|
        redis.hget item_key, Cartman.config.quantity_field
      }.inject(0){|sum,quantity| sum += quantity.to_i}
    end

    def total
      items.collect { |item|
        item.cost
      }.inject(BigDecimal("0")){|sum,cost| sum += cost}
    end

    def ttl
      redis.ttl key
    end

    def destroy!
      keys = line_item_keys
      keys << key
      keys << index_key
      keys << index_keys
      keys.flatten!
      redis.pipelined do
        keys.each do |key|
          redis.del key
        end
      end
    end

    def touch
      keys_to_expire = line_item_keys
      keys_to_expire << key
      if redis.exists index_key
        keys_to_expire << index_key
        keys_to_expire << index_keys
        keys_to_expire.flatten!
      end
      redis.pipelined do
        keys_to_expire.each do |item|
          redis.expire item, Cartman.config.cart_expires_in
        end
      end
      redis.hincrby self.class.versions_key, version_key, 1
    end

    def version
      redis.hget(self.class.versions_key, version_key).to_i
    end

    def reassign(new_id)
      if redis.exists key
        new_index_keys = items.collect { |item|
          index_key_for(item, new_id)
        }
        redis.rename key, key(new_id)
        redis.rename index_key, index_key(new_id)
        index_keys.zip(new_index_keys).each do |key, value|
          redis.rename key, value
        end
      end
      @uid = new_id
    end

    def cache_key
      "cart/#{@uid}-#{version}"
    end

    private

    def key(id=@uid)
      "cartman:cart:#{id}"
    end

    def index_key(id=@uid)
      key(id) + ":index"
    end

    def version_key(id=@uid)
      id
    end

    def self.versions_key
      "cartman:cart:versions"
    end

    def index_keys(id=@uid)
      redis.keys "#{index_key(id)}:*"
    end

    def index_key_for(object, id=@uid)
      case object
      when Hash
        index_key(id) + ":#{object[:type]}:#{object[:id]}"
      when Item
        index_key(id) + ":#{object.type}:#{object.id}"
      else
        index_key(id) + ":#{object.class}:#{object.id}"
      end
    end

    def line_item_ids
      redis.smembers key
    end

    def line_item_keys
      line_item_ids.collect{ |id| "cartman:line_item:#{id}" }
    end

    def get_item(id)
      Item.new(id, @uid, redis.hgetall("cartman:line_item:#{id}").inject({}){|hash,(k,v)| hash[k.to_sym] = v; hash})
    end

    private

    def redis
      Cartman.config.redis
    end
  end
end
