require "test_helper"

module Sources
  class WeiboTest < ActiveSupport::TestCase
    setup do
      # Skip in CI to work around test failures due to rate limiting by Weibo.
      skip if ENV["CI"].present?
    end

    context "A post with multiple pictures" do
      setup do
        @site = Sources::Strategies.find("https://www.weibo.com/5501756072/J2UNKfbqV?type=comment#_rnd1590548401855")
      end

      should "extract all the image urls" do
        urls = %w[
          https://wx1.sinaimg.cn/large/0060kO5aly1gezsyt5xvhj30ok0sgtc9.jpg
          https://wx3.sinaimg.cn/large/0060kO5aly1gezsyuaas1j30go0sgjtj.jpg
          https://wx3.sinaimg.cn/large/0060kO5aly1gezsys1ai9j30gi0sg0v9.jpg
        ]
        assert_equal(urls, @site.image_urls)
      end

      should "get the correct commentary" do
        assert_not_nil(@site.artist_commentary_desc)
      end

      should "get the profile url" do
        assert_equal("https://www.weibo.com/u/5501756072", @site.profile_url)
      end

      should "set the right source" do
        assert_equal("https://www.weibo.com/5501756072/J2UNKfbqV", @site.canonical_url)
      end

      should "download an image" do
        assert_downloaded(134_721, @site.image_url)
      end

      should "get the tags" do
        tags = [
          %w[fgo https://s.weibo.com/weibo/fgo],
          %w[Alter组 https://s.weibo.com/weibo/Alter组],
        ]
        assert_equal(tags, @site.tags)
      end

      should "find the correct artist" do
        @artist = FactoryBot.create(:artist, name: "nipi27", url_string: "https://www.weibo.com/u/5501756072")
        assert_equal([@artist], @site.artists)
      end
    end

    context "A deleted or not existing picture" do
      should "still find the artist name" do
        site = Sources::Strategies.find("https://www.weibo.com/5501756072/AsdAsdAsd")
        artist = FactoryBot.create(:artist, name: "nipi27", url_string: "https://www.weibo.com/u/5501756072")

        assert_equal([artist], site.artists)
      end
    end

    context "A post with video" do
      should "get the correct video" do
        site = Sources::Strategies.find("https://www.weibo.com/5501756072/IF9fugHzj")

        assert_downloaded(7_676_656, site.image_url)
      end
    end

    context "A direct image sample upload" do
      should "get the largest version" do
        sample = Sources::Strategies.find("https://wx3.sinaimg.cn/mw690/a00fa34cly1gf62g2n8z3j21yu2jo1ky.jpg")

        assert_equal("https://wx3.sinaimg.cn/large/a00fa34cly1gf62g2n8z3j21yu2jo1ky.jpg", sample.image_url)
      end
    end

    context "A multi-page upload" do
      should "set the right source" do
        url = "https://wx1.sinaimg.cn/large/7eb64558gy1fnbryriihwj20dw104wtu.jpg"
        ref = "https://photo.weibo.com/2125874520/wbphotos/large/mid/4194742441135220/pid/7eb64558gy1fnbryb5nzoj20dw10419t"
        site = Sources::Strategies.find(url, ref)

        assert_equal("https://www.weibo.com/2125874520/FDKGo4Lk0", site.canonical_url)
      end
    end

    context "A deleted url" do
      should "not raise errors" do
        url = "https://weibo.com/5265069929/LiLnMENgs"
        assert_nothing_raised { Sources::Strategies.find(url).to_h }
      end
    end

    context "A m.weibo.cn/detail url" do
      should "work" do
        @site = Sources::Strategies.find("https://m.weibo.cn/detail/4506950043618873")

        assert_equal(%w[
          https://wx1.sinaimg.cn/large/0060kO5aly1gezsyt5xvhj30ok0sgtc9.jpg
          https://wx3.sinaimg.cn/large/0060kO5aly1gezsyuaas1j30go0sgjtj.jpg
          https://wx3.sinaimg.cn/large/0060kO5aly1gezsys1ai9j30gi0sg0v9.jpg
        ], @site.image_urls)

        assert_equal("https://www.weibo.com/5501756072/J2UNKfbqV", @site.page_url)
        assert_equal("https://www.weibo.com/5501756072/J2UNKfbqV", @site.canonical_url)
        assert_equal(%w[fgo Alter组], @site.tags.map(&:first))
        assert_equal("阿尔托莉雅厨", @site.artist_name)
      end
    end

    context "normalizing for source" do
      should "normalize correctly" do
        source1 = "https://www.weibo.com/3150932560/H4cFbeKKA?from=page_1005053150932560_profile&wvr=6&mod=weibotime"
        source2 = "https://photo.weibo.com/2125874520/wbphotos/large/mid/4242129997905387/pid/7eb64558ly1friyzhj44lj20dw2qxe81"
        source3 = "https://m.weibo.cn/status/4173757483008088?luicode=20000061&lfid=4170879204256635"
        source4 = "https://tw.weibo.com/SEINEN/4098035921690224"

        assert_equal("https://www.weibo.com/3150932560/H4cFbeKKA", Sources::Strategies.normalize_source(source1))
        assert_equal("https://m.weibo.cn/detail/4242129997905387", Sources::Strategies.normalize_source(source2))
        assert_equal("https://m.weibo.cn/status/4173757483008088", Sources::Strategies.normalize_source(source3))
        assert_equal("https://m.weibo.cn/detail/4098035921690224", Sources::Strategies.normalize_source(source4))
      end

      should "avoid normalizing unnormalizable urls" do
        bad_source1 = "https://weibo.com/u/"
        bad_source2 = "https://www.weibo.com/4ubergine/photos"

        assert_equal(bad_source1, Sources::Strategies.normalize_source(bad_source1))
        assert_equal(bad_source2, Sources::Strategies.normalize_source(bad_source2))
      end
    end
  end
end
