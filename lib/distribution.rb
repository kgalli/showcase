class Distribution
  attr_reader :name

  def initialize(name)
    @name = name
  end

  def ami_id
    case name
    when "debian-7"
      "ami-86896dee" # hvm
      # "ami-3776795e"
    when "ubuntu-12.04"
      "ami-1eab0176" # hvm
      # "ami-0b9c9f62"
    when "ubuntu-14.04"
      "ami-8afb51e2" # hvm
      # "ami-018c9568"
    when "fedora-20"
      "ami-6e7da906" # hvm
    else
      raise "don't know how to launch ec2 vm for #{distribution}"
    end
  end

  def username
    case name
    when /ubuntu/
      "ubuntu"
    when /debian/
      "admin"
    when /fedora/
      "fedora"
    else
      "root"
    end
  end

  def codename
    case name
    when "debian-7"
      "wheezy"
    when "ubuntu-12.04"
      "precise"
    when "ubuntu-14.04"
      "trusty"
    when "fedora-20"
      "fedora20"
    else
      raise "don't know the codename mapping for #{distribution}"
    end
  end

  def osfamily
    case name
    when /debian/, /ubuntu/
      "debian"
    when /fedora/, /redhat/, /centos/
      "redhat"
    end
  end

  def root_device
    case osfamily
    when "debian"
      "/dev/xvda"
    when "redhat"
      "/dev/sda1"
    else
      fail "no root_device set"
    end
  end
end
