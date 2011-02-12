/**
 * Mustache template engine for D
 *
 * Implemented according to $(WEB mustache.github.com/mustache.5.html, mustache(5)).
 *
 * Copyright: Copyright Masahiro Nakagawa 2011-.
 * License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
 * Authors:   Masahiro Nakagawa
 */
module mustache;

import std.conv;
import std.string;
import std.traits;
import std.variant;


template Mustache(String = string)
{
    final class Context
    {
      private:
        enum SectionType
        {
            nil, value, func, list
        }

        struct Section
        {
            SectionType type;

            union
            {
                String[String]          value;
                String delegate(String) func;  // String delegate(String) delegate()?
                Context[]               list;
            }

            this(String[String] v)
            {
                type  = SectionType.value;
                value = v;
            }

            this(String delegate(String) f)
            {
                type = SectionType.func;
                func = f;
            }

            this(Context c)
            {
                type = SectionType.list;
                list = [c];
            }

            /* nothrow : AA's length is not nothrow */
            bool empty() const
            {
                final switch (type) {
                case SectionType.nil:
                    return true;
                case SectionType.value:
                    return !value.length;  // Why?
                case SectionType.func:
                    return func is null;
                case SectionType.list:
                    return !list.length;
                }
            }
        }

        Context         parent;
        String[String]  variables;
        Section[String] sections;


      public:
        this(Context context = null)
        {
            parent = context;
        }

        /**
         * Gets $(D_PARAM key)'s value. This method does not search Section.
         *
         * Params:
         *  key = key string to search
         *
         * Returns:
         *  a $(D_PARAM key) associated value.
         *
         * Throws:
         *  a RangeError if $(D_PARAM key) does not exist.
         */
        nothrow String opIndex(String key) const
        {
            return variables[key];
        }

        /**
         * Assigns $(D_PARAM value)(automatically convert to String) to $(D_PARAM key) field.
         *
         * If you try to assign associative array or delegate,
         * This method assigns $(D_PARAM value) as Section.
         *
         * Params:
         *  value = some type value to assign
         *  key   = key string to assign
         */
        void opIndexAssign(T)(T value, String key)
        {
            static if (isAssociativeArray!(T))
            {
                static if (is(T V : V[K], K : String))
                {
                    String[String] aa;

                    static if (is(V == String))
                        aa = value;
                    else
                        foreach (k, v; value) aa[k] = to!String(v);

                    sections[key] = Section(aa);
                }
                else static assert(false, "Non-supported Associative Array type");
            }
            else static if (is(T == delegate))
            {
                static if (is(T D == S delegate(S), S : String))
                    sections[key] = Section(value);
                else static assert(false, "Non-supported delegate type");
            }
            else
            {
                variables[key] = to!String(value);
            }
        }

        /**
         * Gets $(D_PARAM key)'s section value for Phobos friends.
         *
         * Params*
         *  key = key string to get
         *
         * Returns:
         *  section wrapped Variant.
         */
        Variant section(String key)
        {
            auto p = key in sections;
            if (!p)
                return Variant.init;

            Variant v = void;

            final switch (p.type) {
            case SectionType.nil:
                v = Variant.init;
             case SectionType.value:
                v = p.value;
            case SectionType.func:
                v = p.func;
            case SectionType.list:
                v = p.list;
           }

            return v;
        }

        /**
         * Adds new context to $(D_PARAM key)'s section. This method overwrites with
         * list type if you already assigned other type to $(D_PARAM key)'s section.
         *
         * Params:
         *  key  = key string to add
         *  size = reserve size for avoiding reallocation
         *
         * Returns:
         *  new Context object that added to $(D_PARAM key) section list. 
         */
        Context addSubContext(String key, lazy size_t size = 1)
        {
            auto c = new Context(this);
            auto p = key in sections;
            if (!p || p.type != SectionType.list) {
                sections[key] = Section(c);
                sections[key].list.reserve(size);
            } else {
                sections[key].list ~= c;
            }

            return c;
        }


      private:
        /**
         * Fetches $(D_PARAM)'s value. This method follows parent context.
         *
         * Params:
         *  key = key string to fetch
         * 
         * Returns:
         *  a $(D_PARAM key) associated value.　null if key does not exist.
         */
        nothrow String fetch(String key) const
        {
            auto result = key in variables;
            if (result !is null)
                return *result;

            if (parent is null)
                return null;

            return parent.fetch(key);
        }

        nothrow SectionType fetchableSectionType(String key) const
        {
            auto result = key in sections;
            if (result !is null)
                return result.type;

            if (parent is null)
                return SectionType.nil;

            return parent.fetchableSectionType(key);
        }

        nothrow const(Result) fetchSection(Result, SectionType type, string name)(String key) const
        {
            auto result = key in sections;
            if (result !is null && result.type == type)
                return mixin("result." ~ to!String(type));

            if (parent is null)
                return null;

            return mixin("parent.fetch" ~ name ~ "(key)");
        }

        alias fetchSection!(Context[],               SectionType.list,  "List")  fetchList;
        alias fetchSection!(String delegate(String), SectionType.func,  "Func")  fetchFunc;
        alias fetchSection!(String[String],          SectionType.value, "Value") fetchValue;
    }

    unittest
    {
        Context context = new Context();

        context["name"] = "Red Bull";
        assert(context["name"] == "Red Bull");
        context["price"] = 275;
        assert(context["price"] == "275");

        { // list
            foreach (i; 100..105) {
                auto sub = context.addSubContext("sub");
                sub["num"] = i;

                foreach (b; [true, false]) {
                    auto subsub = sub.addSubContext("subsub");
                    subsub["To be or not to be"] = b;
                }
            }

            foreach (i, sub; context.fetchList("sub")) {
                assert(sub.fetch("name") == "Red Bull");
                assert(sub["num"] == to!String(i + 100));

                foreach (j, subsub; sub.fetchList("subsub")) {
                    assert(subsub.fetch("price") == to!String(275));
                    assert(subsub["To be or not to be"] == to!String(j == 0));
                }
            }
        }
        { // value
            String[String] aa = ["name" : "Ritsu"];

            context["Value"] = aa;
            assert(context.fetchValue("Value")["name"] == aa["name"]);
            // @@@BUG@@@ Why following assert raises signal?
            //assert(context.fetchValue("Value") == aa);
            //writeln(context.fetchValue("Value") == aa);  // -> true
        }
        { // func
            auto func = (String str) { return "<b>" ~ str ~ "</b>"; };

            context["Wrapped"] = func;
            assert(context.fetchFunc("Wrapped")("Ritsu") == func("Ritsu"));
        }
    }


  private:
    /**
     * Mustache's node types
     */
    enum NodeType
    {
        text,     /// outside tag
        var,      /// {{}} or {{{}}} or {{&}}
        section,  /// {{#}} or {{^}}
        partial   /// {{<}}
    }


    /**
     * Represents a Mustache node. Currently prototype.
     */
    struct Node
    {
        NodeType type;

        union
        {
            String text;

            struct
            {
                String key;
                bool   flag;    // true is inverted or true is unescape
                Node[] childs;  // for section
            }
        }


        /**
         * Constructs with arguments.
         *
         * Params:
         *   t = raw text
         */
        this(String t)
        {
            type = NodeType.text;
            text = t;
        }

        /**
         * ditto
         *
         * Params:
         *   t = Mustache's node type
         *   k = key string of tag
         *   f = invert? or escape?
         */
        this(NodeType t, String k, lazy bool f = false)
        {
            type = t;
            key  = k;
            flag = f;
        }

        /**
         * Represents the internal status as a string.
         *
         * Returns:
         *  stringized node representation.
         */
        string toString() const
        {
            string result;

            switch (type) {
            case NodeType.text:
                result = "[T : " ~ text ~ "]";
                break;
            case NodeType.var:
                result = "[" ~ (flag ? "E" : "V") ~ " : " ~ key ~ "]";
                break;
            case NodeType.section:
                result = "[" ~ (flag ? "I" : "S") ~ " : " ~ key ~ ", [ ";
                foreach (ref node; childs)
                    result ~= node.toString() ~ " ";
                result ~= "]";
                break;
            case NodeType.partial:
                result = "[P : " ~ key ~ "]";
                break;
            }

            return result;
        }

        unittest
        {
            Node section;
            Node[] nodes, childs;

            nodes ~= Node("Hi ");
            nodes ~= Node(NodeType.var, "name");
            nodes ~= Node(NodeType.partial, "redbull");
            {
                childs ~= Node("Ritsu is ");
                childs ~= Node(NodeType.var, "attr", true);
                section = Node(NodeType.section, "ritsu", false);
                section.childs = childs;
                nodes ~= section;
            }

            assert(to!string(nodes) == "[[T : Hi ], [V : name], [P : redbull], "
                                       "[S : ritsu, [ [T : Ritsu is ] [E : attr] ]]");
        }
    }
}