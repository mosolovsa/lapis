config = require "lapis.config"
config.default_config.postgres = {backend: "pgmoon"}
config.reset true

db = require "lapis.db.postgres"
import Model from require "lapis.db.postgres.model"
import stub_queries, assert_queries from require "spec.helpers"

describe "lapis.db.model.relations", ->
  get_queries, mock_query = stub_queries!

  with old = assert_queries
    assert_queries = (expected, opts) ->
      old expected, get_queries!, opts

  local models

  before_each ->
    models = {}
    package.loaded.models = models

  it "should make belongs_to getter", ->
    mock_query "SELECT", { { id: 101 } }

    models.Users = class extends Model
      @primary_key: "id"

    models.CoolUsers = class extends Model
      @primary_key: "user_id"

    class Posts extends Model
      @relations: {
        {"user", belongs_to: "Users"}
        {"cool_user", belongs_to: "CoolUsers", key: "owner_id"}
      }

    post = Posts!
    post.user_id = 123
    post.owner_id = 99

    assert post\get_user!
    assert post\get_user!

    post\get_cool_user!

    assert_queries {
      'SELECT * from "users" where "id" = 123 limit 1'
      'SELECT * from "cool_users" where "user_id" = 99 limit 1'
    }

  it "should make belongs_to getter with inheritance", ->
    mock_query "SELECT", { { id: 101 } }

    models.Users = class extends Model
      @primary_key: "id"

    class Posts extends Model
      @relations: {
        {"user", belongs_to: "Users"}
      }

      get_user: =>
        with user = super!
          user.color = "green"

    post = Posts!
    post.user_id = 123
    assert.same {
      id: 101
      color: "green"
    }, post\get_user!

  it "caches nil result from belongs_to_fetch", ->
    mock_query "SELECT", {}

    models.Users = class extends Model
      @primary_key: "id"

    class Posts extends Model
      @relations: {
        {"user", belongs_to: "Users"}
      }

    post = Posts!
    post.user_id = 123

    assert.same nil, post\get_user!
    assert.same nil, post\get_user!
    assert.same 1, #get_queries!

  it "should make fetch getter", ->
    called = 0

    class Posts extends Model
      @relations: {
        { "thing", fetch: =>
          called += 1
          "yes"
        }
      }

    post = Posts!
    post.user_id = 123

    assert.same "yes", post\get_thing!
    assert.same "yes", post\get_thing!
    assert.same 1, called

    assert_queries {}

  it "should make a fetch with preload", ->
    called = 0

    class Posts extends Model
      @relations: {
        { "thing"
          fetch: => "yes"
          preload: (objects, opts) ->
            for object in *objects
              continue if object.skip_me
              object.thing = called
              called += 1
        }
      }

    one = Posts!

    two = Posts!
    two.skip_me = true

    three = Posts!
    four = Posts!

    Posts\preload_relations {one, two, three}, "thing"

    assert.same 0, one\get_thing!
    assert.same nil, two\get_thing!
    assert.same 1, three\get_thing!
    assert.same "yes", four\get_thing!

    import LOADED_KEY from require "lapis.db.model.relations"

    for item in *{one, two, three}
      assert.true item[LOADED_KEY].thing

    assert.true four[LOADED_KEY].thing

  it "should make belongs_to getters for extend syntax", ->
    mock_query "SELECT", { { id: 101 } }

    models.Users = class extends Model
      @primary_key: "id"

    m = Model\extend "the_things", {
      relations: {
        {"user", belongs_to: "Users"}
      }
    }

    obj = m!
    obj.user_id = 101


    assert obj\get_user! == obj\get_user!

    assert_queries {
      'SELECT * from "users" where "id" = 101 limit 1'
    }

  it "should make has_one getter", ->
    mock_query "SELECT", { { id: 101 } }

    models.Users = class Users extends Model
      @relations: {
        {"user_profile", has_one: "UserProfiles"}
      }

    models.UserProfiles = class UserProfiles extends Model

    user = Users!
    user.id = 123
    user\get_user_profile!

    assert_queries {
      'SELECT * from "user_profiles" where "user_id" = 123 limit 1'
    }

  it "fails with composite primary key on has_one", ->
    mock_query "SELECT", { { id: 111, id2: 222 } }

    models.Users = class Users extends Model
      @primary_key: {"a_id", "b_id"}
      @relations: {
        {"user_profile", has_one: "UserProfiles"}
        {"user_profile_with_key", has_one: "UserProfiles", key: {
          id: "a_id"
          id2: "b_id"
        }}
      }

    models.UserProfiles = class UserProfiles extends Model

    user = Users!
    user.a_id = 111
    user.b_id = 222

    assert.has_error(
      -> user\get_user_profile!
      "Model UsersRelations has composite primary keys, you must specify column mapping directly with `key`"
    )

    assert.has_error(
      -> Users\preload_relations { user }, "user_profile"
      "Model UsersRelations has composite primary keys, you must specify column mapping directly with `key`"
    )

    user\get_user_profile_with_key!

    Users\preload_relations { user }, "user_profile_with_key"

    assert_queries {
      {
        'SELECT * from "user_profiles" where "id2" = 222 AND "id" = 111 limit 1'
        'SELECT * from "user_profiles" where "id" = 111 AND "id2" = 222 limit 1'
      }
      {
        'SELECT * from "user_profiles" where ("id2", "id") in ((222, 111))'
        'SELECT * from "user_profiles" where ("id", "id2") in ((111, 222))'
      }
    }

  it "should make has_one getter with custom key", ->
    mock_query "SELECT", { { id: 101 } }

    models.UserData = class extends Model

    models.Users = class Users extends Model
      @relations: {
        {"data", has_one: "UserData", key: "owner_id"}
      }

    user = Users!
    user.id = 123
    assert user\get_data!

    assert_queries {
      'SELECT * from "user_data" where "owner_id" = 123 limit 1'
    }

  it "makes has_one getter with composite key", ->
    mock_query "SELECT", { { id: 101 } }

    models.UserPageData = class extends Model

    models.UserPage = class extends Model
      @relations: {
        {"data", has_one: "UserPageData", key: {
          "user_id", "page_id"
        }}
      }

    up = models.UserPage!
    up.user_id = 99
    up.page_id = 234

    assert up\get_data!

    up2 = models.UserPage!
    up2.user_id = nil
    up2.page_id = 'hello'

    assert up2\get_data!

    assert_queries {
      {
        'SELECT * from "user_page_data" where "user_id" = 99 AND "page_id" = 234 limit 1'
        'SELECT * from "user_page_data" where "page_id" = 234 AND "user_id" = 99 limit 1'
      }
      {
        [[SELECT * from "user_page_data" where "user_id" IS NULL AND "page_id" = 'hello' limit 1]]
        [[SELECT * from "user_page_data" where "page_id" = 'hello' AND "user_id" IS NULL limit 1]]
      }
    }


  it "should make has_one getter key and local key", ->
    mock_query "SELECT", { { id: 101, thing_email: "leafo@leafo" } }

    models.Things = class extends Model

    models.Users = class Users extends Model
      @relations: {
        {"data", has_one: "Things", local_key: "email", key: "thing_email"}
      }

    user = Users!
    user.id = 123
    user.email = "leafo@leafo"
    assert user\get_data!

    assert_queries {
      [[SELECT * from "things" where "thing_email" = 'leafo@leafo' limit 1]]
    }

  it "should make has_one getter with where clause", ->
    mock_query "SELECT", { { id: 101 } }

    models.UserData = class extends Model

    models.Users = class Users extends Model
      @relations: {
        {"data", has_one: "UserData", key: "owner_id", where: { state: "good"} }
      }

    user = Users!
    user.id = 123
    assert user\get_data!

    assert_queries {
      {
        [[SELECT * from "user_data" where "owner_id" = 123 AND "state" = 'good' limit 1]]
        [[SELECT * from "user_data" where "state" = 'good' AND "owner_id" = 123 limit 1]]
      }
    }

  it "makes has_one getter with composite key with custom local names", ->

    mock_query "SELECT", { { id: 101 } }

    models.UserPageData = class extends Model

    models.UserPage = class extends Model
      @relations: {
        {"data", has_one: "UserPageData", key: {
          user_id: "alpha_id"
          page_id: "beta_id"
        }}
      }

    up = models.UserPage!
    up.alpha_id = 99
    up.beta_id = 234

    assert up\get_data!

    assert_queries {
      {
        'SELECT * from "user_page_data" where "user_id" = 99 AND "page_id" = 234 limit 1'
        'SELECT * from "user_page_data" where "page_id" = 234 AND "user_id" = 99 limit 1'
      }
    }

  it "should make has_many paginated getter", ->
    mock_query "SELECT", { { id: 101 } }

    models.Posts = class extends Model
    models.Users = class extends Model
      @relations: {
        {"posts", has_many: "Posts"}
        {"more_posts", has_many: "Posts", where: {color: "blue"}}
      }

    user = models.Users!
    user.id = 1234

    -- offset paginator
    user\get_posts_paginated!\get_page 1
    user\get_posts_paginated!\get_page 2

    user\get_more_posts_paginated!\get_page 2

    user\get_posts_paginated(per_page: 44)\get_page 3

    -- offset ordered paginator
    user\get_posts_paginated(ordered: {"id"})\get_page!
    user\get_posts_paginated(ordered: {"id"})\get_page 1023

    user\get_posts_paginated(order: "desc", ordered: {"created_at", "id"})\get_page "2020-1-1", 238

    assert_queries {
      'SELECT * from "posts" where "user_id" = 1234 LIMIT 10 OFFSET 0'
      'SELECT * from "posts" where "user_id" = 1234 LIMIT 10 OFFSET 10'
      {
        [[SELECT * from "posts" where "user_id" = 1234 AND "color" = 'blue' LIMIT 10 OFFSET 10]]
        [[SELECT * from "posts" where "color" = 'blue' AND "user_id" = 1234 LIMIT 10 OFFSET 10]]
      }
      'SELECT * from "posts" where "user_id" = 1234 LIMIT 44 OFFSET 88'
      'SELECT * from "posts" where "user_id" = 1234 order by "posts"."id" ASC limit 10'
      'SELECT * from "posts" where "posts"."id" > 1023 and ("user_id" = 1234) order by "posts"."id" ASC limit 10'

      [[SELECT * from "posts" where ("posts"."created_at", "posts"."id") < ('2020-1-1', 238) and ("user_id" = 1234) order by "posts"."created_at" desc, "posts"."id" desc limit 10]]
    }


  it "should make has_many getter", ->
    models.Posts = class extends Model
    models.Users = class extends Model
      @relations: {
        {"posts", has_many: "Posts"}
        {"more_posts", has_many: "Posts", where: {color: "blue"}}
        {"fresh_posts", has_many: "Posts", order: "id desc"}
      }

    user = models.Users!
    user.id = 1234

    user\get_posts!
    user\get_posts!

    user\get_more_posts!
    user\get_fresh_posts!

    assert_queries {
      'SELECT * from "posts" where "user_id" = 1234'
      {
        [[SELECT * from "posts" where "user_id" = 1234 AND "color" = 'blue']]
        [[SELECT * from "posts" where "color" = 'blue' AND "user_id" = 1234]]
      }
      'SELECT * from "posts" where "user_id" = 1234 order by id desc'
    }

  it "should make has_many getter with composite key", ->
    mock_query "SELECT", {
      { id: 101, user_id: 99, page_id: 234 }
      { id: 102, user_id: 99, page_id: 234 }
    }

    models.UserPageData = class extends Model

    models.UserPage = class extends Model
      @relations: {
        {"data", has_many: "UserPageData", key: {
          "user_id", "page_id"
        }}
      }

    up = models.UserPage!
    up.user_id = 99
    up.page_id = 234

    assert.same {
      { id: 101, user_id: 99, page_id: 234 }
      { id: 102, user_id: 99, page_id: 234 }
    }, up\get_data!

    up2 = models.UserPage!
    up2.user_id = 99
    up2.page_id = nil
    assert up2\get_data!

    assert_queries {
      {
        'SELECT * from "user_page_data" where "user_id" = 99 AND "page_id" = 234'
        'SELECT * from "user_page_data" where "page_id" = 234 AND "user_id" = 99'
      }
      {
        'SELECT * from "user_page_data" where "user_id" = 99 AND "page_id" IS NULL'
        'SELECT * from "user_page_data" where "page_id" IS NULL AND "user_id" = 99'
      }
    }



  it "should create relations for inheritance", ->
    class Base extends Model
      @relations: {
        {"user", belongs_to: "Users"}
      }

    class Child extends Base
      @relations: {
        {"category", belongs_to: "Categories"}
      }

    assert Child.get_user, "expecting get_user"
    assert Child.get_category, "expecting get_category"
    assert.same nil, rawget Child, "get_user"

  describe "polymorphic belongs to", ->
    local Foos, Bars, Bazs, Items

    before_each ->
      models.Foos = class Foos extends Model
      models.Bars = class Bars extends Model
        @primary_key: "frog_index"

      models.Bazs = class Bazs extends Model

      Items = class Items extends Model
        @relations: {
          {"object", polymorphic_belongs_to: {
            [1]: {"foo", "Foos"}
            [2]: {"bar", "Bars"}
            [3]: {"baz", "Bazs"}
          }}
        }

    it "should model_for_object_type", ->
      assert Foos == Items\model_for_object_type 1
      assert Foos == Items\model_for_object_type "foo"

      assert Bars == Items\model_for_object_type 2
      assert Bars == Items\model_for_object_type "bar"

      assert Bazs == Items\model_for_object_type 3
      assert Bazs == Items\model_for_object_type "baz"

      assert.has_error ->
        Items\model_for_object_type 4

      assert.has_error ->
        Items\model_for_object_type "bun"

    it "should object_type_for_model", ->
      assert.same 1, Items\object_type_for_model Foos
      assert.same 2, Items\object_type_for_model Bars
      assert.same 3, Items\object_type_for_model Bazs

      assert.has_error ->
        Items\object_type_for_model Items

    it "should object_type_for_object", ->
      assert.same 1, Items\object_type_for_object Foos!
      assert.same 2, Items\object_type_for_object Bars!
      assert.same 3, Items\object_type_for_object Bazs

      assert.has_error ->
        Items\object_type_for_model {}

    it "should call getter", ->
      mock_query "SELECT", { { id: 101 } }

      for i, {type_id, cls} in ipairs {{1, Foos}, {2, Bars}, {3, Bazs}}
        item = Items\load {
          object_type: type_id
          object_id: i * 33
        }

        obj = item\get_object!

        obj.__class == cls

        obj2 = item\get_object!

        assert.same obj, obj2

      assert_queries {
        'SELECT * from "foos" where "id" = 33 limit 1'
        'SELECT * from "bars" where "frog_index" = 66 limit 1'
        'SELECT * from "bazs" where "id" = 99 limit 1'
      }


    it "should call preload with empty", ->
      Items\preload_objects {}

      assert_queries {
      }

    it "should call preload", ->
      k = 0
      n = ->
        k += 1
        k

      items = {
        Items\load {
          object_type: 1
          object_id: n!
        }

        Items\load {
          object_type: 2
          object_id: n!
        }

        Items\load {
          object_type: 1
          object_id: n!
        }

        Items\load {
          object_type: 1
          object_id: n!
        }
      }

      Items\preload_objects items

      assert_queries {
        'SELECT * from "foos" where "id" in (1, 3, 4)'
        'SELECT * from "bars" where "frog_index" in (2)'
      }

    it "preloads with fields", ->
      items = {
        Items\load {
          object_type: 1
          object_id: 111
        }

        Items\load {
          object_type: 2
          object_id: 112
        }

        Items\load {
          object_type: 3
          object_id: 113
        }
      }

      Items\preload_objects items, fields: {
        bar: "a, b"
        baz: "c, d"
      }

      assert_queries {
        'SELECT * from "foos" where "id" in (111)'
        'SELECT a, b from "bars" where "frog_index" in (112)'
        'SELECT c, d from "bazs" where "id" in (113)'
      }

  it "finds relation", ->
    import find_relation from require "lapis.db.model.relations"

    class Posts extends Model
      @relations: {
        {"user", belongs_to: "Users"}
        {"cool_user", belongs_to: "CoolUsers", key: "owner_id"}
      }

    class BetterPosts extends Posts
      @relations: {
        {"tags", has_many: "Tags"}
      }

    assert.same {"user", belongs_to: "Users"}, (find_relation Posts, "user")
    assert.same nil, (find_relation Posts, "not there")
    assert.same {"cool_user", belongs_to: "CoolUsers", key: "owner_id"},
      (find_relation BetterPosts, "cool_user")

  describe "clear_loaded_relation", ->
    it "clears loaded relation cached with value", ->
      mock_query "SELECT", {
        {id: 777, name: "hello"}
      }
      models.Users = class Users extends Model

      class Posts extends Model
        @relations: {
          {"user", belongs_to: "Users"}
        }

      post = Posts\load {
        id: 1
        user_id: 1
      }

      post\get_user!
      post\get_user!

      assert.same 1, #get_queries!

      assert.not.nil post.user

      post\clear_loaded_relation "user"

      assert.nil post.user

      post\get_user!

      assert.same 2, #get_queries!

    it "clears loaded relation cached with nil", ->
      mock_query "SELECT", {}

      models.Users = class Users extends Model

      class Posts extends Model
        @relations: {
          {"user", belongs_to: "Users"}
        }

      post = Posts\load {
        id: 1
        user_id: 1
      }

      post\get_user!
      post\get_user!

      assert.same 1, #get_queries!

      post\clear_loaded_relation "user"
      post\get_user!

      assert.same 2, #get_queries!

  describe "preload_relations", ->
    it "preloads relations that return empty", ->
      mock_query "SELECT", {}

      models.Dates = class Dates extends Model
      models.Users = class Users extends Model
      models.Tags = class Tags extends Model

      class Posts extends Model
        @relations: {
          {"user", belongs_to: "Users"}
          {"date", has_one: "Dates"}
          {"tags", has_many: "Tags"}
        }

      post = Posts\load {
        id: 888
        user_id: 234
      }

      Posts\preload_relations {post}, "user", "date", "tags"

      assert_queries {
        [[SELECT * from "users" where "id" in (234)]]
        [[SELECT * from "dates" where "post_id" in (888)]]
        [[SELECT * from "tags" where "post_id" in (888)]]
      }

      import LOADED_KEY from require "lapis.db.model.relations"

      assert.same {
        user: true
        date: true
        tags: true
      }, post[LOADED_KEY]

      before_count = #get_queries!

      post\get_user!
      post\get_date!
      post\get_tags!

      assert.same, before_count, #get_queries!

    it "preloads has_many with order and fields", ->
      models.Tags = class Tags extends Model

      class Posts extends Model
        @relations: {
          {"tags", has_many: "Tags", order: "a desc"}
        }

      Posts\preload_relation {Posts\load id: 123}, "tags", {
        fields: "a,b"
        order: "b asc"
      }
      assert_queries {
        [[SELECT a,b from "tags" where "post_id" in (123) order by b asc]]
      }

    it "preloads has_many with composite key", ->
      mock_query "SELECT", {
        { id: 101, user_id: 99, page_id: 234 }
        { id: 102, user_id: 99, page_id: 234 }
        { id: 103, user_id: 100, page_id: 234 }
      }

      models.UserPageData = class extends Model

      models.UserPage = class UserPage extends Model
        @relations: {
          {"data", has_many: "UserPageData", key: {
            "user_id", "page_id"
          }}
        }

      user_pages = {
        UserPage\load {
          user_id: 99
          page_id: 234
        }

        UserPage\load {
          user_id: 100
          page_id: 234
        }

        UserPage\load {
          user_id: 100
          page_id: 300
        }
      }

      UserPage\preload_relation user_pages, "data"

      assert_queries {
        'SELECT * from "user_page_data" where ("user_id", "page_id") in ((99, 234), (100, 234), (100, 300))'
      }

      import LOADED_KEY from require "lapis.db.model.relations"
      for user_page in *user_pages
        assert.true user_page[LOADED_KEY].data

      assert.same {
        { id: 101, user_id: 99, page_id: 234 }
        { id: 102, user_id: 99, page_id: 234 }
      }, user_pages[1].data

      assert.same {
        { id: 103, user_id: 100, page_id: 234 }
      }, user_pages[2].data

      assert.same {}, user_pages[3].data

    it "preloads has_one with key and local_key", ->
      mock_query "SELECT", {
        { id: 99, thing_email: "notleafo@leafo" }
        { id: 101, thing_email: "leafo@leafo" }
      }

      models.Things = class extends Model

      models.Users = class Users extends Model
        @relations: {
          {"thing", has_one: "Things", local_key: "email", key: "thing_email"}
        }

      user = Users!
      user.id = 123
      user.email = "leafo@leafo"

      Users\preload_relations {user}, "thing"

      assert_queries {
        [[SELECT * from "things" where "thing_email" in ('leafo@leafo')]]
      }

      assert.same {
        id: 101
        thing_email: "leafo@leafo"
      }, user.thing

    it "preloads has_one with where", ->
      mock_query "SELECT", {
        { thing_id: 123, name: "whaz" }
      }

      models.Files = class Files extends Model

      class Things extends Model
        @relations: {
          {"beta_file"
            has_one: "Files"
            where: { deleted: false }
          }
        }

      thing = Things\load { id: 123 }
      Things\preload_relations { thing }, "beta_file"

      assert.same {
        thing_id: 123
        name: "whaz"
      }, thing.beta_file

      assert_queries {
        [[SELECT * from "files" where "thing_id" in (123) and "deleted" = FALSE]]
      }

    it "preloads has_one with composite key", ->
      import LOADED_KEY from require "lapis.db.model.relations"

      mock_query "SELECT", {
        {id: 1, user_id: 11, page_id: 101}
      }

      models.UserPageData = class extends Model

      models.UserPage = class UserPage extends Model
        @relations: {
          {"data", has_one: "UserPageData", key: {
            "user_id", "page_id"
          }}
        }

      user_pages = {
        UserPage\load {
          user_id: 10
          page_id: 100
        }

        UserPage\load {
          user_id: 11
          page_id: 101
        }
      }

      UserPage\preload_relation user_pages, "data"

      assert_queries {
        [[SELECT * from "user_page_data" where ("user_id", "page_id") in ((10, 100), (11, 101))]]
      }

      assert.same {
        {
          user_id: 10
          page_id: 100
          [LOADED_KEY]: { data: true }
        }

        {
          user_id: 11
          page_id: 101
          data: {
            id: 1, user_id: 11, page_id: 101
          }
          [LOADED_KEY]: { data: true }
        }
      }, user_pages


    it "preloads has_many with order and name", ->
      mock_query "SELECT", {
        { primary_thing_id: 123, name: "whaz" }
      }

      models.Tags = class Tags extends Model

      class Things extends Model
        @relations: {
          {"cool_tags"
            has_many: "Tags"
            order: "name asc"
            where: { deleted: false }
            key: "primary_thing_id"
          }
        }

      thing = Things\load { id: 123 }
      Things\preload_relations {thing}, "cool_tags"
      assert.same {
        { primary_thing_id: 123, name: "whaz" }
      }, thing.cool_tags

      assert_queries {
        [[SELECT * from "tags" where "primary_thing_id" in (123) and "deleted" = FALSE order by name asc]]
      }

    it "preloads belongs_to with correct name", ->
      mock_query "SELECT", {
        { id: 1, name: "last" }
        { id: 2, name: "first" }
        { id: 3, name: "default" }
      }

      models.Topics = class Topics extends Model

      class Categories extends Model
        @relations: {
          {"last_topic", belongs_to: "Topics"}
          {"first_topic", belongs_to: "Topics"}
          {"topic", belongs_to: "Topics"}
        }

      cat = Categories\load {
        id: 1243
        last_topic_id: 1
        first_topic_id: 2
        topic_id: 3
      }

      Categories\preload_relations {cat}, "last_topic", "first_topic", "topic"
      assert.same 3, #get_queries!

      assert.same {
        id: 1
        name: "last"
      }, cat\get_last_topic!, cat.last_topic

      assert.same {
        id: 2
        name: "first"
      }, cat\get_first_topic!, cat.first_topic

      assert.same {
        id: 3
        name: "default"
      }, cat\get_topic!, cat.topic

      assert.same 3, #get_queries!

    it "preloads has_one with correct name", ->
      mock_query "SELECT", {
        {user_id: 1, name: "cool dude"}
      }

      models.UserData = class UserData extends Model

      class Users extends Model
        @relations: {
          {"data", has_one: "UserData"}
        }

      user = Users\load id: 1
      Users\preload_relations {user}, "data"
      assert.same {user_id: 1, name: "cool dude"}, user.data, user\get_data!

    it "finds inherited preloaders", ->
      models.Users = class Users extends Model

      class SimplePosts extends Model
        @relations: {
          {"user", belongs_to: "Users"}
        }

      class JointPosts extends SimplePosts
        @relations: {
          {"second_user", belongs_to: "Users"}
        }

      p = JointPosts\load {
        id: 999
        user_id: 1
        second_user_id: 2
      }

      JointPosts\preload_relations {p}, "user", "second_user"

  describe "has_one", ->
    it "preloads when using custom keys", ->
      mock_query "SELECT", {
        {user_id: 100, name: "first"}
        {user_id: 101, name: "second"}
      }

      models.UserItems = class UserItems extends Model
        @primary_key: "user_id"

        @relations: {
          {"application", has_one: "ItemApplications", key: "user_id"}
        }

        new: (user_id) =>
          @user_id = assert user_id, "missing user id"

      models.ItemApplications = class ItemApplications extends Model
        id = 1
        new: (user_id) =>
          @user_id = assert user_id, "missing user id"
          @id = id
          id += 1

      ui = UserItems 100
      a = assert ui\get_application!, "expected to get relation"
      assert.same 100, a.user_id

      ui2 = UserItems 101
      UserItems\preload_relations {ui2}, "application"
      a = assert ui2.application, "expected to get relation"
      assert.same 101, a.user_id

      assert_queries {
        [[SELECT * from "item_applications" where "user_id" = 100 limit 1]]
        [[SELECT * from "item_applications" where "user_id" in (101)]]
      }

  describe "generic preload", ->
    local preload

    before_each ->
      import preload from require "lapis.db.model"

      models.Users = class Users extends Model
        @relations: {
          {"tags", has_many: "Tags"}
          {"user_data", has_one: "UserData"}
          {"account", belongs_to: "Accounts"}
        }

        new: (@id) =>
          assert @id, "missing id"

      models.Tags = class Tags extends Model
        @relations: {
          {"owner", has_one: "Users"}
        }

      models.UserData = class UserData extends Model
        @relations: {
          {"images", has_many: "Images"}
        }

      models.Accounts = class Accounts extends Model
      models.Images = class Images extends Model

    it "preloads basic relations", ->
      user = models.Users 10
      user.account_id = 99

      preload { user }, "tags", "user_data", "account"

      assert_queries {
        [[SELECT * from "tags" where "user_id" in (10)]]
        [[SELECT * from "user_data" where "user_id" in (10)]]
        [[SELECT * from "accounts" where "id" in (99)]]
      }

    it "preloads nested relations", ->
      mock_query 'from "tags"', {
        models.Tags\load {
          id: 252
          user_id: 10
        }
        models.Tags\load {
          id: 311
          user_id: 10
        }
      }

      mock_query 'from "user_data"', {
        models.UserData\load {
          id: 32
          user_id: 10
        }
      }

      user = models.Users 10
      user.account_id = 99

      preload { user }, "account", {
        tags: { "owner" }
        user_data: {"images"}
      }

      assert_queries {
        [[SELECT * from "accounts" where "id" in (99)]]
        [[SELECT * from "images" where "user_data_id" in (32)]]
        [[SELECT * from "tags" where "user_id" in (10)]]
        [[SELECT * from "user_data" where "user_id" in (10)]]
        [[SELECT * from "users" where "tag_id" in (252, 311)]]
      }, sorted: true


    it "preloads nested fetch relations", ->
      models.Collections = class Collection extends Model
        @relations: {
          {"user",
            fetch: => {}
            preload: (collections) ->
              for c in *collections
                c.user = models.Users\load {
                  id: 10
                }
              true
          }

          {"things",
            many: true
            fetch: => {}
            preload: (collections) ->
              for c in *collections
                c.things = {
                  models.Users\load {
                    id: 11
                  }

                  models.Users\load {
                    id: 12
                  }
                }

              true

          }
        }

        new: (@id) =>
          assert @id, "missing id"

      collection = models.Collections 44
      preload { collection }, {
        user: "tags"
        things: { "user_data", "tags" }
      }

      assert_queries {
        -- TODO: homogeneous preload should be able to merge these queries
        [[SELECT * from "tags" where "user_id" in (10)]]
        [[SELECT * from "tags" where "user_id" in (11, 12)]]
        [[SELECT * from "user_data" where "user_id" in (11, 12)]]
      }, sorted: true

    describe "optional relations", ->
      it "single optional relation", ->
        class OtherThing extends Model
          new: (opts) =>
            for k,v in pairs opts
              @[k] = v

        class Thing extends Model
          @relations: {
            {"other_thing"
              fetch: => error "preload should not fetch"

              preload: (list) ->
                for item in *list
                  item.other_thing = OtherThing {
                    thing: item
                  }
            }
          }

        class EmptyThing extends Model

        assert.has_error(
          ->
            preload {EmptyThing!, EmptyThing!}, "other_thing"
          "Model EmptyThing doesn't have preloader for other_thing"
        )

        assert.has_error(
          ->
            preload {Thing!, Thing!}, "missing_thing"
          "Model Thing doesn't have preloader for missing_thing"
        )


        empty_things = {EmptyThing!, EmptyThing!}
        preload empty_things, "?other_thing"

        things = {Thing!, Thing!}
        preload things, "?missing_thing"


        preload things, other_thing: "?unknown_thing"

        assert.truthy things[1].other_thing
        assert.equal things[1], things[1].other_thing.thing

        assert.truthy things[2].other_thing
        assert.equal things[2], things[2].other_thing.thing

      it "many optional relation", ->
        class OtherThing extends Model
          new: (opts) =>
            for k,v in pairs opts
              @[k] = v

        class ThingConnector extends Model
          @relations: {
            {"the_thing"
              fetch: => error "preload should not fetch"

              preload: (list) ->
                for item in *list
                  item.the_thing = OtherThing {
                    parent: item
                  }
            }
          }

          new: (opts) =>
            for k,v in pairs opts
              @[k] = v

        class Thing extends Model
          @relations: {
            {"other_things"
              many: true
              fetch: => error "preload should not fetch"

              preload: (list) ->
                for item in *list
                  item.other_things = {
                    OtherThing {
                      idx: 1
                      parent: item
                    }
                    ThingConnector {
                      idx: 2
                      parent: item
                    }
                  }
            }
          }

        things = {Thing!, Thing!}
        preload things, other_things: "?the_thing"

        for thing_idx=1,2
          assert.truthy things[thing_idx].other_things

          for other_things_idx=1,2
            assert.equal things[thing_idx], things[thing_idx].other_things[other_things_idx].parent

          assert.nil things[thing_idx].other_things[1].the_thing

          -- the thing connector instance
          assert.truthy things[thing_idx].other_things[2].the_thing


      it "optional into more relations", ->
        class Friend extends Model
          new: (opts) =>
            for k,v in pairs opts
              @[k] = v

        class TheThing extends Model
          @relations: {
            {"friend"
              fetch: => error "preload should not fetch"
              preload: (items) ->
                for item in *items
                  item.friend = Friend {
                    parent: item
                  }
            }
          }

        class Thing extends Model
          @relations: {
            {"friend"
              fetch: => error "preload should not fetch"
              preload: (items) ->
                for item in *items
                  item.friend = Friend {
                    parent: item
                  }

            }
          }

        class Thong extends Model
          @relations: {
            {"the_things"
              fetch: => error "preload should not fetch"
              many: true
              preload: (items) ->
                for item in *items
                  item.the_things = {
                    TheThing parent: item
                    TheThing parent: item
                  }
            }
          }


        things = {Thing!, Thong!, Thong!}
        preload things, {
          "?friend"
          "?the_things": "friend"
        }

        do -- thing
          assert.truthy things[1].friend
          assert.nil things[1].the_things

          assert.equal things[1], things[1].friend.parent


        do -- thong 1
          assert.nil things[2].friend
          assert.truthy things[2].the_things

          for the_thing in *things[2].the_things
            assert.truthy the_thing.friend
            assert.equal the_thing, the_thing.friend.parent

        do -- thong 2
          assert.nil things[3].friend
          assert.truthy things[3].the_things

          for the_thing in *things[3].the_things
            assert.truthy the_thing.friend
            assert.equal the_thing, the_thing.friend.parent




