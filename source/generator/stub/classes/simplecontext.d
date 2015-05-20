/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module generator.stub.classes.simplecontext;

import std.algorithm : among, map;
import std.ascii : newline;

import clang.c.index;
import clang.Cursor;

import dsrcgen.cpp;

import generator.stub.classes.access;
import generator.analyzer : visitAst, IdStack, logNode, VisitNodeModule;
import generator.stub.convert : toString;
import generator.stub.containers : VariableContainer, CallbackContainer;
import generator.stub.mangling;
import generator.stub.misc : parmDeclToTypeName;
import generator.stub.types;

import generator.stub.classes.class_methods : MethodContext;

/** Translate a ClassDecl to a stub implementation.
 *
 * The generate stub implementation have an interface that the user can control
 * the data flow from stub -> SUT.
 */
public struct ClassContext {
    VisitNodeModule!CppHdrImpl visitor_stack;
    alias visitor_stack this;

    @disable this();

    /** Context for stubbing a class with a specific prefix.
     * Params:
     *  prefix = prefix to use for the name of the stub class.
     *  name = name of the c++ class being stubbed.
     */
    this(const StubPrefix prefix, const OnlyStubVirtual only_virt,
        const CppClassName name, const CppNesting nesting, const CppNsStack ns_nesting) {
        import std.array : join;

        this.prefix = prefix;
        this.only_virtual = only_virt;
        this.name = name;

        this.data_ns = StubNs(prefix ~ "Internal" ~ name);

        CallbackNs cb_ns = prefix ~ "Callback" ~ name;
        CallbackPrefix cp = "I";
        CallbackStruct cb_st = prefix ~ "Callback";
        CountStruct cnt_st = prefix ~ "Counter";
        StaticStruct st_st = prefix ~ "Static";

        this.vars = VariableContainer(prefix, cb_ns, cp, data_ns, name);
        this.callbacks = CallbackContainer(cb_ns, cp);
        this.class_nesting = CppClassNesting(nesting.map!(a => cast(string) a).join("::"));
        this.ns_nesting = CppNsNesting(ns_nesting.map!(a => cast(string) a).join("::"));
    }

    void translate(ref Cursor cursor, ref CppModule hdr, ref CppModule impl) {
        void doTraversal(ref ClassContext ctx, CppHdrImpl top) {
            ctx.push(top);
            auto c = Cursor(cursor);
            visitAst!ClassContext(c, this);
        }

        auto top = CppHdrImpl(hdr, impl);
        auto internal = CppHdrImpl(hdr.base, impl.base);
        internal.hdr.suppressIndent(1);
        internal.impl.suppressIndent(1);
        auto stub = CppHdrImpl(hdr.base, impl.base);
        stub.hdr.suppressIndent(1);
        stub.impl.suppressIndent(1);

        doTraversal(this, stub);

        // forward declaration of stubbed class.
        internal.hdr.stmt(E("class") ~ E(mangleToStubClassName(prefix, name).str));
        internal.hdr.sep(2);

        callbacks.renderInterfaces(internal.hdr);
        doDataStruct(data_ns, ns_nesting, vars, internal.hdr, internal.impl);
        doDataStructInit(prefix, data_ns, CppClassName(prefix ~ name), vars,
            this.class_code.hdr, stub.impl);

        hdr.sep;
    }

    /** Traverse cursor and translate a subset of kinds.
     * It defers translation of class methods to specialized translator for those.
     * The reason is that a class can have multiple interfaces it inherit from
     * and the generated stub must implement all of them.
     */
    bool apply(Cursor c) {
        bool descend = true;
        logNode(c, depth);

        switch (c.kind) with (CXCursorKind) {
        case CXCursor_ClassDecl:
            // Cursor sent is the root of the class so first time we descend
            // because it is the class asked of us to translate.  Further
            // ClassDecl found are nested classes. Those are taken care of by
            // other code and thus ignored.
            final switch (classdecl_used) {
            case true:
                descend = false;
                break;
            case false:
                this.classdecl_used = true;
                ///TODO change to using the name mangling function.
                auto stubname = CppClassName(cast(string) prefix ~ name);
                push(classTranslator(prefix, class_nesting, name, current.get));
                class_code = current.get;
                MethodContext(prefix, stubname, access_spec, only_virtual).translate(c,
                    vars, callbacks, current.get);
                break;
            }
            break;
        case CXCursor_Constructor:
            push(CppHdrImpl(consumeAccessSpecificer(access_spec, current.hdr), current.impl));
            ctorTranslator(c, prefix, current.hdr, current.impl);
            descend = false;
            break;
        case CXCursor_Destructor:
            push(CppHdrImpl(consumeAccessSpecificer(access_spec, current.hdr), current.impl));
            dtorTranslator(c, prefix, vars, callbacks, current.hdr, current.impl);
            descend = false;
            break;
        case CXCursor_CXXAccessSpecifier:
            access_spec = CppAccessSpecifier(c.access.accessSpecifier);
            break;
        default:
            break;
        }
        return descend;
    }

private:
    bool classdecl_used;
    CppHdrImpl class_code; // top of the new class created.
    immutable StubPrefix prefix;
    immutable CppClassName name;
    immutable CppClassNesting class_nesting;
    immutable CppNsNesting ns_nesting;
    immutable OnlyStubVirtual only_virtual;

    VariableContainer vars;
    CallbackContainer callbacks;
    CppAccessSpecifier access_spec;

    immutable StubNs data_ns;
}

private:

void doDataStruct(const StubNs data_ns, const CppNsNesting ns_nesting,
    ref VariableContainer vars, ref CppModule hdr, ref CppModule impl) {
    if (vars.length == 0)
        return;

    auto ns_hdr = hdr.namespace(data_ns.str);
    ns_hdr.suppressIndent(1);
    auto ns_impl = impl.namespace(data_ns.str);
    ns_impl.suppressIndent(1);

    vars.render(ns_nesting, ns_hdr, ns_impl);
    hdr.sep(2);
    impl.sep(2);
}

void doDataStructInit(const StubPrefix prefix, const StubNs data_ns,
    const CppClassName class_name, VariableContainer vars, ref CppModule hdr, ref CppModule impl) {
    if (vars.length == 0)
        return;

    CppClassName getter_cls = mangleToStubDataClass(data_ns, prefix);
    CppMethodName getter_func = CppMethodName("Get" ~ prefix.str);
    CppVariable getter_var = CppVariable(prefix ~ "_data");

    with (hdr.public_) {
        method(false, getter_cls ~ "&", getter_func.str, false);
        sep(2);
    }
    with (hdr.private_) {
        stmt(E("mutable") ~ E(getter_cls.str) ~ E(getter_var.str));
    }

    with (impl.method_body(getter_cls.str ~ "&", class_name.str, getter_func.str, false)) {
        return_(getter_var.str);
    }
    impl.sep(2);
}

CppHdrImpl classTranslator(StubPrefix prefix, CppClassNesting nesting,
    CppClassName name, ref CppHdrImpl hdr_impl) {
    auto doHeader(ref CppModule hdr) {
        auto node = hdr;
        string stub_class = prefix.str ~ name.str;
        with (hdr) {
            auto n = nesting.str;
            node = class_(stub_class, "public " ~ n ~ (n.length == 0 ? "" : "::") ~ name.str);
            sep();
        }

        return node;
    }

    return CppHdrImpl(doHeader(hdr_impl.hdr), hdr_impl.impl);
}

void ctorTranslator(Cursor c, const StubPrefix prefix, ref CppModule hdr, ref CppModule impl) {
    void doHeader(CppClassName name, const ref TypeName[] params) {
        auto p = params.toString;
        auto node = hdr.ctor(name.str, p);
    }

    void doImpl(const CppClassName name, const TypeName[] params) {
        auto p = params.toString;
        auto node = impl.ctor_body(name.str, p);
        impl.sep(2);
    }

    CppClassName name = prefix ~ c.spelling;
    auto params = parmDeclToTypeName(c);
    doHeader(name, params);
    doImpl(name, params);
}

void dtorTranslator(Cursor c, const StubPrefix prefix, ref VariableContainer vars,
    ref CallbackContainer callbacks, ref CppModule hdr, ref CppModule impl) {
    import std.string : removechars;

    void doHeader(CppClassName name, CppMethodName callback_name, ref CppModule hdr) {
        auto node = hdr.dtor(c.func.isVirtual, name.str);
        hdr.sep(2);

        callbacks.push(CppType("void"), callback_name, TypeName[].init);
        vars.push(NameMangling.Callback, cast(CppType) callback_name,
            cast(CppVariable) callback_name, callback_name);
        vars.push(NameMangling.CallCounter, CppType("unsigned"),
            cast(CppVariable) callback_name, callback_name);
    }

    void doImpl(const CppClassName name, const CppClassName stub_name,
        const CppMethodName callback_name, ref CppModule impl) {
        auto data = mangleToStubDataClassVariable(prefix);
        auto getter = mangleToStubDataGetter(callback_name, TypeKindVariable[].init);
        auto counter = mangleToStubStructMember(prefix,
            NameMangling.CallCounter, CppVariable(callback_name.str));
        auto callback = mangleToStubStructMember(prefix, NameMangling.Callback,
            CppVariable(callback_name.str));

        with (impl.dtor_body(stub_name.str)) {
            stmt("%s.%s().%s++".format(data.str, getter.str, counter.str));
            sep(2);
            with (if_(E(data.str).e(getter.str)("").e(callback.str) ~ E("!= 0"))) {
                stmt(E(data.str).e(getter.str)("").e(callback.str ~ "->" ~ callback_name.str)(""));
            }
        }
        impl.sep(2);
    }

    CppClassName name = c.spelling.removechars("~");
    CppClassName stub_name = prefix ~ name;
    CppMethodName callback_name = prefix ~ "Dtor";

    doHeader(stub_name, callback_name, hdr);
    doImpl(name, stub_name, callback_name, impl);
}
