require "./spec_helper"

describe Pattern do
  it "works" do
    a = nil
    b = nil
    c = nil
    d = nil
    Pattern.match! [1, [2, 3], 4], {a, {b, __splat(c)}, d = Int32}
    a.should eq(1)
    b.should eq(2)
    c.should eq([3])
    d.should eq(4)
    typeof(a).should eq(Int32 | Array(Int32))
    typeof(b).should eq(Int32)
    typeof(c).should eq(Array(Int32))
    typeof(d).should eq(Int32)
  end
end
