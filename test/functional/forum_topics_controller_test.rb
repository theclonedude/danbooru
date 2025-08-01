require 'test_helper'

class ForumTopicsControllerTest < ActionDispatch::IntegrationTest
  def default_search_order(items)
    ->{ items.each { |val| val.reload }.sort_by(&:updated_at).reverse }
  end

  context "The forum topics controller" do
    setup do
      @user = create(:user)
      @other_user = create(:user)
      @mod = create(:moderator_user, name: "okuu")

      @forum_topic = create(:forum_topic, creator: @user, title: "my forum topic", original_post: build(:forum_post, creator: @user, topic: @forum_topic, body: "xxx"))
    end

    context "for a level restricted topic" do
      setup do
        @forum_topic.update(min_level: User::Levels::MODERATOR, updater: @mod)
      end

      should "not allow users to see the topic" do
        get_auth forum_topic_path(@forum_topic), @user
        assert_response 403
      end

      should "not bump the forum for users without access" do
        @gold_user = create(:gold_user)

        # An open topic should bump...
        @open_topic = create(:forum_topic, creator: @gold_user)
        assert_equal(true, @gold_user.reload.has_forum_been_updated?)

        # Marking it as read should clear it...
        post_auth mark_all_as_read_forum_topics_path, @gold_user
        assert_redirected_to(forum_topics_path)
        assert_equal(false, @gold_user.reload.has_forum_been_updated?)

        # Then adding an unread private topic should not bump.
        create(:forum_post, topic: @forum_topic, creator: @mod)
        assert_equal(false, @gold_user.reload.has_forum_been_updated?)
      end
    end

    context "show action" do
      should "render" do
        get forum_topic_path(@forum_topic)
        assert_response :success
      end

      should "record a topic visit for html requests" do
        get_auth forum_topic_path(@forum_topic), @user
        @user.reload
        assert_not_nil(@user.last_forum_read_at)
      end

      should "not record a topic visit for non-html requests" do
        get_auth forum_topic_path(@forum_topic), @user, params: {format: :json}
        @user.reload
        assert_equal(Time.zone.parse("1960-01-01"), @user.last_forum_read_at)
      end

      should "render for atom feed" do
        get forum_topic_path(@forum_topic), params: {:format => :atom}
        assert_response :success
      end

      should "raise an error if the user doesn't have permission to view the topic" do
        @forum_topic.update(min_level: User::Levels::ADMIN, updater: @user)
        get_auth forum_topic_path(@forum_topic), @user

        assert_response 403
      end
    end

    context "index action" do
      setup do
        @sticky_topic = create(:forum_topic, is_sticky: true, creator: @user, original_post: build(:forum_post, creator: @user))
        @other_topic = create(:forum_topic, creator: @user, original_post: build(:forum_post, creator: @user))
        @mod_topic = create(:forum_topic, creator: @mod, min_level: User::Levels::MODERATOR, original_post: build(:forum_post, creator: @user))
        create(:bulk_update_request, user: @mod, forum_topic: @forum_topic)
        create(:tag_alias, forum_topic: @other_topic)
      end

      should "list public forum topics for members" do
        get forum_topics_path

        assert_response :success
        assert_select "a.forum-post-link", count: 1, text: @sticky_topic.title
        assert_select "a.forum-post-link", count: 1, text: @other_topic.title
      end

      should "not list stickied topics first for JSON responses" do
        get forum_topics_path, params: {format: :json}
        forum_topics = JSON.parse(response.body)
        assert_equal(default_search_order([@other_topic, @sticky_topic, @forum_topic]).call.map(&:id), forum_topics.map {|t| t["id"]})
      end

      should "render for atom feed" do
        get forum_topics_path, params: {:format => :atom}
        assert_response :success
      end

      should "render for a sitemap" do
        get forum_topics_path(format: :sitemap)
        assert_response :success
        assert_equal(ForumTopic.visible(User.anonymous).count, response.parsed_body.css("urlset url loc").size)
      end

      should "not show deleted topics for HTML responses by default" do
        create(:forum_topic, is_deleted: true)
        get forum_topics_path

        assert_response :success
        assert_select 'tr[data-is-deleted="true"]', count: 0
        assert_select 'tr[data-is-deleted="false"]', count: 3
      end

      context "with private topics" do
        should "not show private topics to unprivileged users" do
          @other_topic.update!(min_level: User::Levels::MODERATOR, updater: @user)
          get forum_topics_path

          assert_response :success
          assert_select "a.forum-post-link", count: 1, text: @sticky_topic.title
          assert_select "a.forum-post-link", count: 0, text: @other_topic.title
        end

        should "show private topics to privileged users" do
          @other_topic.update!(min_level: User::Levels::MODERATOR, updater: @user)
          get_auth forum_topics_path, @mod

          assert_response :success
          assert_select "a.forum-post-link", count: 1, text: @sticky_topic.title
          assert_select "a.forum-post-link", count: 1, text: @other_topic.title
        end
      end

      context "with search conditions" do
        context "as a user" do
          setup do
            CurrentUser.user = @user
          end

          should respond_to_search({}).with { default_search_order([@sticky_topic, @other_topic, @forum_topic]) }
          should respond_to_search(order: "id").with { [@other_topic, @sticky_topic, @forum_topic] }
          should respond_to_search(title_matches: "forum").with { @forum_topic }
          should respond_to_search(title_matches: "bababa").with { [] }
          should respond_to_search(is_sticky: "true").with { @sticky_topic }
          should respond_to_search(category: "General").with { [@forum_topic, @other_topic, @sticky_topic] }
          should respond_to_search(category: "general").with { [@forum_topic, @other_topic, @sticky_topic] }
          should respond_to_search(category: "Tags").with { [] }
          should respond_to_search(category_id: "0").with { [@forum_topic, @other_topic, @sticky_topic] }
          should respond_to_search(is_private: "true").with { [] }
          should respond_to_search(is_private: "false").with { [@forum_topic, @other_topic, @sticky_topic] }
          should respond_to_search(min_level: "None").with { [@forum_topic, @other_topic, @sticky_topic] }
          should respond_to_search(min_level: "none").with { [@forum_topic, @other_topic, @sticky_topic] }
          should respond_to_search(min_level: "0").with { [@forum_topic, @other_topic, @sticky_topic] }
          should respond_to_search(min_level: "Member").with { [] }
          should respond_to_search(min_level: "Moderator").with { [] }
          should respond_to_search(min_level_id: "<10").with { [@forum_topic, @other_topic, @sticky_topic] }

          context "using includes" do
            should respond_to_search(forum_posts: {body_matches: "xxx"}).with { @forum_topic }
            should respond_to_search(has_bulk_update_requests: "true").with { @forum_topic }
            should respond_to_search(has_tag_aliases: "true").with { @other_topic }
            should respond_to_search(creator_name: "okuu").with { [] }
          end
        end

        context "as a moderator" do
          setup do
            CurrentUser.user = @mod
          end

          should respond_to_search({}).with { default_search_order([@sticky_topic, @other_topic, @mod_topic, @forum_topic]) }
          should respond_to_search(is_private: "false").with { [@forum_topic, @other_topic, @sticky_topic] }
          should respond_to_search(is_private: "true").with { [@mod_topic] }
          should respond_to_search(min_level: "None").with { [@forum_topic, @other_topic, @sticky_topic] }
          should respond_to_search(min_level: "Member").with { [] }
          should respond_to_search(min_level: "Moderator").with { [@mod_topic] }
          should respond_to_search(min_level: "0").with { [@forum_topic, @other_topic, @sticky_topic] }
          should respond_to_search(min_level: User::Levels::MODERATOR.to_s).with { [@mod_topic] }
          should respond_to_search(min_level_id: ">0").with { [@mod_topic] }

          context "using includes" do
            should respond_to_search(creator_name: "okuu").with { [@mod_topic] }
          end
        end
      end

      context "when listing topics" do
        should "always show topics as read for anonymous users" do
          get forum_topics_path
          assert_select 'tr[data-is-read="false"]', count: 0
        end

        should "show topics as read after viewing them" do
          get_auth forum_topics_path, @user
          assert_response :success
          assert_select 'tr[data-is-read="false"]', count: 3

          get_auth forum_topic_path(@forum_topic.id), @user
          assert_response :success

          get_auth forum_topics_path, @user
          assert_response :success
        end

        should "show topics as read after marking all as read" do
          get_auth forum_topics_path, @user
          assert_response :success
          assert_select 'tr[data-is-read="false"]', count: 3

          post_auth mark_all_as_read_forum_topics_path, @user
          assert_response 302

          get_auth forum_topics_path, @user
          assert_response :success
          assert_select 'tr[data-is-read="false"]', count: 0
        end

        should "show topics on page 2 as read after marking all as read" do
          get_auth forum_topics_path(page: 2, limit: 1), @user
          assert_response :success
          assert_select 'tr[data-is-read="false"]', count: 1

          post_auth mark_all_as_read_forum_topics_path, @user
          assert_response 302

          get_auth forum_topics_path(page: 2, limit: 1), @user
          assert_response :success
          assert_select 'tr[data-is-read="false"]', count: 0
        end
      end
    end

    context "edit action" do
      should "render if the editor is the creator of the topic" do
        get_auth edit_forum_topic_path(@forum_topic), @user
        assert_response :success
      end

      should "render if the editor is a moderator" do
        get_auth edit_forum_topic_path(@forum_topic), @mod
        assert_response :success
      end

      should "fail if the editor is not the creator of the topic and is not a moderator" do
        get_auth edit_forum_topic_path(@forum_topic), @other_user
        assert_response(403)
      end
    end

    context "new action" do
      should "render" do
        get_auth new_forum_topic_path, @user
        assert_response :success
      end
    end

    context "create action" do
      should "create a new forum topic and post" do
        assert_difference(["ForumPost.count", "ForumTopic.count"], 1) do
          post_auth forum_topics_path, @user, params: { forum_topic: { title: "bababa", original_post_attributes: { body: "xaxaxa" }}}
        end

        forum_topic = ForumTopic.last
        assert_redirected_to(forum_topic_path(forum_topic))
        assert_equal(@user, forum_topic.creator)
        assert_equal(@user, forum_topic.updater)
        assert_equal(@user, forum_topic.original_post.creator)
        assert_equal(@user, forum_topic.original_post.updater)
      end

      should "rate limit the creation of new forum topics" do
        Danbooru.config.stubs(:rate_limits_enabled?).returns(true)

        assert_difference(["ForumPost.count", "ForumTopic.count"], 1) do
          post_auth forum_topics_path, @user, params: { forum_topic: { title: "test", original_post_attributes: { body: "test" }}}
          assert_redirected_to forum_topic_path(ForumTopic.last)
        end

        assert_no_difference(["ForumPost.count", "ForumTopic.count"]) do
          post_auth forum_topics_path, @user, params: { forum_topic: { title: "test", original_post_attributes: { body: "test" }}}
          assert_response 429
        end
      end
    end

    context "update action" do
      should "allow mods to lock forum topics" do
        put_auth forum_topic_path(@forum_topic), @mod, params: { forum_topic: { is_locked: true }}

        assert_redirected_to forum_topic_path(@forum_topic)
        assert_equal(true, @forum_topic.reload.is_locked)
        assert_equal(@mod, @forum_topic.updater)
        assert_equal(@mod, @forum_topic.original_post.updater)
        assert(ModAction.exists?(category: "forum_topic_lock", subject: @forum_topic, creator: @mod))
      end

      should "allow users to update their own topics" do
        put_auth forum_topic_path(@forum_topic), @user, params: { forum_topic: { title: "test" }}

        assert_redirected_to forum_topic_path(@forum_topic)
        assert_equal("test", @forum_topic.reload.title)
        assert_equal(@user, @forum_topic.updater)
        assert_equal(@user, @forum_topic.original_post.updater)
      end

      should "not allow users to update locked topics" do
        @forum_topic.update!(is_locked: true, updater: create(:moderator_user))
        put_auth forum_topic_path(@forum_topic), @user, params: { forum_topic: { title: "test" }}

        assert_response 403
        assert_not_equal("test", @forum_topic.reload.title)
      end

      should "allow mods to update locked topics" do
        @forum_topic.update!(is_locked: true, updater: create(:moderator_user))
        put_auth forum_topic_path(@forum_topic), @mod, params: { forum_topic: { title: "test" }}

        assert_redirected_to forum_topic_path(@forum_topic)
        assert_equal("test", @forum_topic.reload.title)
        assert_equal(@mod, @forum_topic.updater)
        assert_equal(@mod, @forum_topic.original_post.updater)
      end

      should "allow users to update the OP" do
        put_auth forum_topic_path(@forum_topic), @user, params: { forum_topic: { original_post_attributes: { body: "test", id: @forum_topic.original_post.id }}}

        assert_redirected_to forum_topic_path(@forum_topic)
        assert_equal("test", @forum_topic.original_post.reload.body)
        assert_equal(@user, @forum_topic.updater)
        assert_equal(@user, @forum_topic.original_post.updater)
      end
    end

    context "destroy action" do
      should "mark the topic and all posts as deleted" do
        @post = create(:forum_post, topic: @forum_topic, creator: @user)
        delete_auth forum_topic_path(@forum_topic), @mod

        assert_redirected_to(@forum_topic)
        assert_equal(true, @forum_topic.reload.is_deleted?)
        assert_equal(@mod, @forum_topic.updater)
        assert_equal(true, @forum_topic.forum_posts.all?(&:is_deleted?))
        assert_equal(true, @forum_topic.forum_posts.all? { |post| post.updater == @mod })
        assert(ModAction.exists?(category: "forum_topic_delete", subject: @forum_topic, creator: @mod))
      end
    end

    context "undelete action" do
      should "mark the topic and all posts as undeleted" do
        @forum_topic.update!(is_deleted: true, updater: create(:moderator_user))
        post_auth undelete_forum_topic_path(@forum_topic), @mod

        assert_redirected_to(@forum_topic)
        assert_equal(false, @forum_topic.reload.is_deleted?)
        assert_equal(@mod, @forum_topic.updater)
        assert_equal(false, @forum_topic.forum_posts.all?(&:is_deleted?))
        assert_equal(true, @forum_topic.forum_posts.all? { |post| post.updater == @mod })
        assert(ModAction.exists?(category: "forum_topic_undelete", subject: @forum_topic, creator: @mod))
      end
    end
  end
end
