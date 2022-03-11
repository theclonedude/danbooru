# frozen_string_literal: true

# @see Source::URL::Weibo
module Sources
  module Strategies
    class Weibo < Base

      def match?
        Source::URL::Weibo === parsed_url
      end

      def site_name
        parsed_url.site_name
      end

      def image_urls
        if parsed_url.image_url?
          [parsed_url.full_image_url]
        elsif api_response.present?
          if api_response["pics"].present?
            api_response["pics"].pluck("url").map { |url| Source::URL.parse(url).full_image_url }
          elsif api_response.dig("page_info", "type") == "video"
            variants = api_response["page_info"]["media_info"].to_h.values + api_response["page_info"]["urls"].to_h.values
            largest_video = variants.max_by do |variant|
              if /template=(?<width>\d+)x(?<height>\d+)/ =~ variant.to_s
                width.to_i * height.to_i
              else
                0
              end
            end
            [largest_video]
          end
        else
          [url]
        end
      end

      def page_url
        return nil unless api_response.present?

        artist_id = api_response["user"]["id"]
        illust_base62_id = api_response["bid"]
        "https://www.weibo.com/#{artist_id}/#{illust_base62_id}"
      end

      def tags
        return [] if api_response.blank?

        matches = api_response["text"]&.scan(/surl-text">#(.*?)#</).to_a.map { |m| m[0] }
        matches.map do |match|
          [match, "https://s.weibo.com/weibo/#{match}"]
        end
      end

      def profile_urls
        (parsed_url.profile_urls + parsed_referer&.profile_urls.to_a).uniq
      end

      def profile_url
        profile_urls.first
      end

      def artist_name
        api_response&.dig("user", "screen_name")
      end

      def artist_commentary_desc
        return if api_response.blank?

        api_response["text"]
      end

      def dtext_artist_commentary_desc
        DText.from_html(artist_commentary_desc) do |element|
          if element["href"].present?
            href = Addressable::URI.heuristic_parse(element["href"])
            href.site ||= "https://www.weibo.com"
            href.scheme ||= "https"
            element["href"] = href.to_s
          end

          if element["src"].present?
            src = Addressable::URI.heuristic_parse(element["src"])
            src.scheme ||= "https"
            element["src"] = src.to_s
          end
        end
      end

      def normalize_for_source
        parsed_url.normalized_url
      end

      def api_response
        return {} if (mobile_url = parsed_url.mobile_url || parsed_referer&.mobile_url).blank?

        resp = http.cache(1.minute).get(mobile_url)
        json_string = resp.to_s[/var \$render_data = \[(.*)\]\[0\]/m, 1]

        return {} if json_string.blank?

        JSON.parse(json_string)["status"]
      end
      memoize :api_response
    end
  end
end
