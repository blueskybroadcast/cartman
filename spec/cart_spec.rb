require 'spec_helper'

describe Cartman do
  describe Cartman::Cart do
    let(:Bottle) { Struct.new(:id) }
    let(:cart) { Cartman::Cart.new(1) }

    before(:each) do
      Cartman.config.redis.flushdb
    end

    describe "#set_discounted" do
      it "sets new value for discounted" do
        cart.set_discounted 'some code'
        cart.discounted.should be_eql 'some code'
      end

      it "sets new redis value in redis" do
        cart.set_discounted 'some code'
        Cartman.config.redis.get(cart.send(:discounted_key)).should be_eql 'some code'
      end
    end

    describe "#key" do
      it "should return a proper key string" do
        cart.send(:key).should eq("cartman:cart:1")
      end
    end

    describe "#add_item" do
      before(:each) do
        cart.add_item(id: 17, type: "Bottle", name: "Bordeux", unit_cost: 92.12, quantity: 2)
      end

      it "creates a line item key" do
        Cartman.config.redis.exists("cartman:line_item:1").should be_truthy
      end

      it "adds that line item key's id to the cart set" do
        Cartman.config.redis.sismember(cart.send(:key), 1).should be_truthy
      end

      it "should expire the line_item_keys in the amount of time specified" do
        cart.ttl.should eq(Cartman.config.cart_expires_in)
        Cartman.config.redis.ttl("cartman:line_item:1").should eq(Cartman.config.cart_expires_in)
      end

      it "should add an index key to be able to look up by type and ID" do
        Cartman.config.redis.exists("cartman:cart:1:index").should be_truthy
        Cartman.config.redis.sismember("cartman:cart:1:index", "Bottle:17").should be_truthy
      end

      it "should squack if type and/or ID are not set" do
        expect { cart.add_item(id: 18, name: "Cordeux", unit_cost: 92.12, quantity: 2) }.to raise_error("Must specify both :id and :type")
        expect { cart.add_item(type: "Bottle", name: "Cordeux", unit_cost: 92.12, quantity: 2) }.to raise_error("Must specify both :id and :type")
        expect { cart.add_item(name: "Cordeux", unit_cost: 92.12, quantity: 2) }.to raise_error("Must specify both :id and :type")
      end

      it "should return an Item" do
        item = cart.add_item(id: 34, type: "Bottle", name: "Cabernet", unit_cost: 92.12, quantity: 2)
        item.class.should eq(Cartman::Item)
      end
    end

    describe "#remove_item" do
      it "should remove the id from the set, and delete the line_item key" do
        item = cart.add_item(id: 17, type: "Bottle", name: "Bordeux", unit_cost: 92.12, quantity: 2)
        item_id = item._id
        cart.remove_item(item)
        Cartman.config.redis.sismember(cart.send(:key), item_id).should be_falsey
        Cartman.config.redis.exists("cartman:line_item:#{item_id}").should be_falsey
      end

      it "should not delete the indecies for other items" do
        item = cart.add_item(id: 17, type: "Bottle", name: "Bordeux", unit_cost: 92.12, quantity: 2)
        item2 = cart.add_item(id: 18, type: "Bottle", name: "Bordeux", unit_cost: 92.12, quantity: 2)
        Cartman.config.redis.exists("cartman:cart:1:index:Bottle:17").should be_truthy
        Cartman.config.redis.exists("cartman:cart:1:index:Bottle:18").should be_truthy
        cart.remove_item(item)
        Cartman.config.redis.exists("cartman:cart:1:index:Bottle:17").should be_falsey
        Cartman.config.redis.exists("cartman:cart:1:index:Bottle:18").should be_truthy
      end
    end

    describe "#items" do
      before(:each) do
        cart.add_item(id: 17, type: "Bottle", name: "Bordeux", unit_cost: 92.12, quantity: 2)
        cart.add_item(id: 34, type: "Bottle", name: "Cabernet", unit_cost: 92.12, quantity: 2)
        cart.add_item(id: 35, type: "GiftCard", name: "Gift Card", unit_cost: 100.00, quantity: 1)
      end

      it "should return an ItemCollection of Items" do
        cart.items.class.should be(Cartman::ItemCollection)
        cart.items.first.class.should be(Cartman::Item)
        cart.items.first.id.should eq("17")
        cart.items.first.name.should eq("Bordeux")
      end

      it "should return all items in cart if no filter is given" do
        cart.items.size.should eq(3)
      end

      it "should return a subset of the items if a filter is given" do
        cart.items("Bottle").size.should eq(2)
        cart.items("GiftCard").size.should eq(1)
        cart.items("SomethingElse").size.should eq(0)
      end
    end

    describe "#contains?(item)" do
      before(:all) do
        Bottle = Struct.new(:id)
      end

      before(:each) do
        cart.add_item(id: 17, type: "Bottle", name: "Bordeux", unit_cost: 92.12, quantity: 2)
        cart.add_item(id: 34, type: "Bottle", name: "Cabernet", unit_cost: 92.12, quantity: 2)
      end

      it "should be able to tell you that an item in the cart is present" do
        cart.contains?(Bottle.new(17)).should be_truthy
      end

      it "should be able to tell you that an item in the cart is absent" do
        cart.contains?(Bottle.new(20)).should be_falsey
      end

      it "should be able to tell you that an item in the cart is absent if it's been removed" do
        cart.remove_item(cart.items.first)
        cart.contains?(Bottle.new(17)).should be_falsey
        cart.remove_item(cart.items.last)
        cart.contains?(Bottle.new(34)).should be_falsey
      end
    end

    describe "#find(item)" do

      before(:each) do
        cart.add_item(id: 17, type: "Bottle", name: "Bordeux", unit_cost: 92.12, quantity: 2)
        cart.add_item(id: 34, type: "Bottle", name: "Cabernet", unit_cost: 92.12, quantity: 2)
      end

      it "should take some object, and return the Item that corresponds to it" do
        cart.find(Bottle.new(17)).quantity.should eq("2")
        cart.find(Bottle.new(17)).name.should eq("Bordeux")
        cart.find(Bottle.new(34)).name.should eq("Cabernet")
      end

      it "should return nil if the Item is not in the cart" do
        cart.find(Bottle.new(23)).should be(nil)
      end
    end

    describe "#count" do
      it "should return the number of items in the cart" do
        cart.add_item(id: 17, type: "Bottle", name: "Bordeux", unit_cost: 92.12, quantity: 2)
        cart.add_item(id: 34, type: "Bottle", name: "Cabernet", unit_cost: 92.12, quantity: 2)
        cart.count.should eq(2)
      end
    end

    describe "#quantity" do
      it "should return the sum of the default quantity field" do
        cart.add_item(id: 17, type: "Bottle", name: "Bordeux", unit_cost: 92.12, quantity: 2)
        cart.add_item(id: 34, type: "Bottle", name: "Cabernet", unit_cost: 92.12, quantity: 2)
        cart.quantity.should eq(4)
      end

      it "should return the sum of the defined quantity field" do
        Cartman.config do |c|
          c.quantity_field = :qty
        end
        cart.add_item(id: 17, type: "Bottle", name: "Bordeux", unit_cost: 92.12, qty: 2)
        cart.add_item(id: 34, type: "Bottle", name: "Cabernet", unit_cost: 92.12, qty: 2)
        cart.quantity.should eq(4)
        Cartman.config do |c|
          c.quantity_field = :quantity
        end
      end
    end

    describe "#total" do
      it "should return 0 when no items are in the cart" do
        cart.total.should eq(0)
      end

      it "should total the default costs field" do
        cart.add_item(id: 17, type: "Bottle", name: "Bordeux", unit_cost: 92.12, quantity: 2)
        cart.add_item(id: 34, type: "Bottle", name: "Cabernet", unit_cost: 92.12, quantity: 2)
        cart.total.should eq(368.48)
      end

      it "should total whatever cost field the user sets" do
        Cartman.config do |c|
          c.unit_cost_field = :unit_cost_in_cents
        end
        cart.add_item(id: 17, type: "Bottle", name: "Bordeux", unit_cost_in_cents: 9212, quantity: 2)
        cart.add_item(id: 34, type: "Bottle", name: "Cabernet", unit_cost_in_cents: 9212, quantity: 2)
        cart.total.should eq(36848)
        Cartman.config do |c|
          c.unit_cost_field = :unit_cost
        end
      end
    end

    describe "#destroy" do
      it "should delete the line_item keys, the index key, and the cart key" do
        cart.set_discounted 'some code'
        cart.add_item(id: 17, type: "Bottle", name: "Bordeux", unit_cost: 92.12, cost_in_cents: 18424, quantity: 2)
        cart.add_item(id: 34, type: "Bottle", name: "Cabernet", unit_cost: 92.12, cost_in_cents: 18424, quantity: 2)
        cart.destroy!
        Cartman.config.redis.exists("cartman:cart:1:discounted").should be_falsey
        Cartman.config.redis.exists("cartman:cart:1").should be_falsey
        Cartman.config.redis.exists("cartman:line_item:1").should be_falsey
        Cartman.config.redis.exists("cartman:line_item:2").should be_falsey
        Cartman.config.redis.exists("cartman:cart:1:index").should be_falsey
        Cartman.config.redis.exists("cartman:cart:1:index:Bottle:17").should be_falsey
      end
    end

    describe "#touch" do
      it "should reset the TTL" do
        cart.add_item(id: 17, type: "Bottle", name: "Bordeux", unit_cost: 92.12, cost_in_cents: 18424, quantity: 2)
        cart.touch
        cart.ttl.should eq(Cartman.config.cart_expires_in)
        Cartman.config.redis.ttl("cartman:cart:1:index").should eq(Cartman.config.cart_expires_in)
        Cartman.config.redis.ttl("cartman:cart:1:index:Bottle:17").should eq(Cartman.config.cart_expires_in)
      end

      it "should record that the cart was updated" do
        cart.add_item(id: 17, type: "Bottle", name: "Bordeux", unit_cost: 92.12, cost_in_cents: 18424, quantity: 2)
        cart.touch
        cart.version.should eq(2)
      end
    end

    describe "#reassign" do
      it "should only change the @uid if no key exists" do
        cart.reassign(2)
        cart.send(:key)[-1].should eq("2")
      end

      it "should rename the key, and index_key if it exists" do
        cart.add_item(id: 17, type: "Bottle", name: "Bordeux", unit_cost: 92.12, cost_in_cents: 18424, quantity: 1)
        cart.add_item(id: 18, type: "Bottle", name: "Merlot", unit_cost: 92.12, cost_in_cents: 18424, quantity: 3)
        cart.quantity.should be(4)
        cart.reassign(2)
        cart.items.size.should be(2)
        Cartman::Cart.new(2).quantity.should be(4)
        Cartman.config.redis.exists("cartman:cart:1").should be_falsey
        Cartman.config.redis.exists("cartman:cart:1:index").should be_falsey
        Cartman.config.redis.exists("cartman:cart:1:index:Bottle:17").should be_falsey
        Cartman.config.redis.exists("cartman:cart:2").should be_truthy
        Cartman.config.redis.exists("cartman:cart:2:index").should be_truthy
        Cartman.config.redis.exists("cartman:cart:2:index:Bottle:17").should be_truthy
        cart.send(:key)[-1].should eq("2")
        cart.add_item(id: 19, type: "Bottle", name: "Bordeux", unit_cost: 92.12, cost_in_cents: 18424, quantity: 2)
        cart.reassign(1)
        cart.items.size.should be(3)
        Cartman.config.redis.exists("cartman:cart:2").should be_falsey
        Cartman.config.redis.exists("cartman:cart:2:index").should be_falsey
        Cartman.config.redis.exists("cartman:cart:1").should be_truthy
        Cartman.config.redis.exists("cartman:cart:1:index").should be_truthy
        cart.send(:key)[-1].should eq("1")
      end
    end

    describe "#cache_key" do
      it "should return /cart/{cart_id}-{version}/" do
        cart.cache_key.should eq("cart/#{cart.instance_variable_get(:@uid)}-#{cart.version}")
      end
    end
  end
end
