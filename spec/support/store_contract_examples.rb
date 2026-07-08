# frozen_string_literal: true

RSpec.shared_examples "a Waitmate store" do
  let(:queue_name) { "checkout" }
  let(:identity) { "session-abc" }

  before { store.expire_stale(queue_name) }

  describe "#enqueue" do
    it "returns position 1 for the first waiter" do
      expect(store.enqueue(queue_name, identity)).to eq(1)
    end

    it "returns incremental positions for later waiters" do
      store.enqueue(queue_name, "first")
      store.enqueue(queue_name, "second")

      expect(store.enqueue(queue_name, "third")).to eq(3)
    end

    it "returns 0 when the identity is already active" do
      store.enqueue(queue_name, identity)
      store.admit(queue_name, 1)

      expect(store.enqueue(queue_name, identity)).to eq(0)
    end

    it "preserves the original position on re-enqueue" do
      store.enqueue(queue_name, "first")
      store.enqueue(queue_name, identity)
      store.enqueue(queue_name, "third")

      expect(store.enqueue(queue_name, identity)).to eq(2)
    end
  end

  describe "#position" do
    it "returns nil for an unknown identity" do
      expect(store.position(queue_name, identity)).to be_nil
    end

    it "returns the 1-based waiting position" do
      store.enqueue(queue_name, "first")
      store.enqueue(queue_name, identity)

      expect(store.position(queue_name, identity)).to eq(2)
    end

    it "returns 0 for an active identity" do
      store.enqueue(queue_name, identity)
      store.admit(queue_name, 1)

      expect(store.position(queue_name, identity)).to eq(0)
    end

    it "returns nil for an expired waiting identity" do
      store.enqueue(queue_name, identity, ttl: 0)
      travel 1.second

      expect(store.position(queue_name, identity)).to be_nil
    end
  end

  describe "#active_count" do
    it "starts at zero" do
      expect(store.active_count(queue_name)).to eq(0)
    end

    it "reflects admitted entries" do
      store.enqueue(queue_name, "first")
      store.enqueue(queue_name, "second")
      store.admit(queue_name, 2)

      expect(store.active_count(queue_name)).to eq(2)
    end

    it "does not exceed capacity" do
      store.enqueue(queue_name, "first")
      store.enqueue(queue_name, "second")
      store.enqueue(queue_name, "third")
      store.admit(queue_name, 2)

      expect(store.active_count(queue_name)).to eq(2)
    end

    it "does not count expired active entries" do
      store.enqueue(queue_name, identity)
      store.admit(queue_name, 1)

      travel 2.hours

      expect(store.active_count(queue_name)).to eq(0)
    end
  end

  describe "#admit" do
    it "admits up to capacity" do
      store.enqueue(queue_name, "first")
      store.enqueue(queue_name, "second")
      store.enqueue(queue_name, "third")

      admitted = store.admit(queue_name, 2)

      expect(admitted).to contain_exactly("first", "second")
      expect(store.active_count(queue_name)).to eq(2)
      expect(store.position(queue_name, "third")).to eq(1)
    end

    it "admits in FIFO order" do
      store.enqueue(queue_name, "early")
      store.enqueue(queue_name, "late")

      expect(store.admit(queue_name, 1)).to eq(["early"])
    end

    it "returns an empty array when no capacity is available" do
      store.enqueue(queue_name, "first")
      store.admit(queue_name, 1)

      expect(store.admit(queue_name, 0)).to be_empty
    end

    it "admits waiting entries when active entries from a prior admission exist" do
      store.enqueue(queue_name, "first")
      store.enqueue(queue_name, "second")
      store.admit(queue_name, 5)

      store.enqueue(queue_name, "third")
      store.enqueue(queue_name, "fourth")

      admitted = store.admit(queue_name, 5)
      expect(admitted).to contain_exactly("third", "fourth")
      expect(store.active_count(queue_name)).to eq(4)
    end

    it "does not admit expired waiting entries" do
      store.enqueue(queue_name, identity, ttl: 0)
      store.enqueue(queue_name, "second")
      travel 1.second

      admitted = store.admit(queue_name, 2)
      expect(admitted).to eq(["second"])
      expect(store.position(queue_name, "second")).to eq(0)
      expect(store.position(queue_name, identity)).to be_nil
    end
  end

  describe "#release" do
    it "removes an active identity" do
      store.enqueue(queue_name, identity)
      store.admit(queue_name, 1)

      expect(store.release(queue_name, identity)).to be true
      expect(store.active_count(queue_name)).to eq(0)
    end

    it "returns false for an unknown identity" do
      expect(store.release(queue_name, identity)).to be false
    end

    it "allows the next queued user to be admitted" do
      store.enqueue(queue_name, "first")
      store.enqueue(queue_name, "second")
      store.enqueue(queue_name, "third")
      store.admit(queue_name, 2)

      expect(store.release(queue_name, "first")).to be true
      expect(store.admit(queue_name, 2)).to include("third")
      expect(store.position(queue_name, "third")).to eq(0)
    end
  end

  describe "#heartbeat" do
    it "extends the TTL of a waiting identity" do
      store.enqueue(queue_name, identity, ttl: 1)
      expect(store.heartbeat(queue_name, identity, ttl: 10)).to be true

      expect(store.position(queue_name, identity)).to eq(1)
    end

    it "extends the TTL of an active identity" do
      store.enqueue(queue_name, identity)
      store.admit(queue_name, 1)

      expect(store.heartbeat(queue_name, identity, ttl: 10)).to be true
    end

    it "returns false for an unknown identity" do
      expect(store.heartbeat(queue_name, identity)).to be false
    end
  end

  describe "#expire_stale" do
    it "removes stale waiting entries" do
      store.enqueue(queue_name, identity, ttl: 0)
      travel 1.second

      expect(store.expire_stale(queue_name)).to eq(waiting: 1, active: 0)
      expect(store.position(queue_name, identity)).to be_nil
    end

    it "removes stale active entries" do
      store.enqueue(queue_name, identity)
      store.admit(queue_name, 1, count: 1)

      travel 2.hours

      expect(store.expire_stale(queue_name)).to eq(waiting: 0, active: 1)
      expect(store.active_count(queue_name)).to eq(0)
    end
  end
end
