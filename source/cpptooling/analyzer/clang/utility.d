// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module cpptooling.analyzer.clang.utility;

import std.typecons : Flag, Yes, No, Nullable;
import logger = std.experimental.logger;

import clang.Cursor : Cursor;
import cpptooling.analyzer.clang.ast.visitor;
import cpptooling.analyzer.clang.type : TypeResult;
import cpptooling.data.symbol.container : Container;

version (unittest) {
    import unit_threaded : Name, shouldEqual;
} else {
    private struct Name {
        string name_;
    }
}

//TODO handle anonymous namespace
//TODO maybe merge with backtrackNode in clang/utility.d?
/** Analyze the scope the declaration/definition reside in by backtracking to
 * the root.
 *
 * TODO allow the caller to determine what cursor kind's are sent to the sink.
 */
void backtrackScope(NodeT, SinkT)(ref const(NodeT) node, scope SinkT sink) {
    import std.algorithm : among;
    import std.range.primitives : put;

    import deimos.clang.index : CXCursorKind;
    import cpptooling.analyzer.clang.type : logNode;

    static if (is(NodeT == Cursor)) {
        Cursor curr = node;
    } else {
        // a Declaration class
        // TODO add a constraint
        Cursor curr = node.cursor;
    }

    int depth = 0;
    while (curr.isValid) {
        debug logNode(curr, depth);

        if (curr.kind.among(CXCursorKind.CXCursor_UnionDecl, CXCursorKind.CXCursor_StructDecl,
                CXCursorKind.CXCursor_ClassDecl, CXCursorKind.CXCursor_Namespace)) {
            put(sink, curr.spelling);
        }

        curr = curr.semanticParent;
        ++depth;
    }
}

//TODO remove the default value for indent.
void put(ref Nullable!TypeResult tr, ref Container container, in uint indent = 0) @safe {
    import cpptooling.analyzer.clang.type : logTypeResult;

    if (!tr.isNull) {
        container.put(tr.primary.kind);
        foreach (e; tr.extra) {
            container.put(e.kind);
        }
    }
}
