const std = @import("std"); const info = @typeInfo(@TypeOf(std.net)); comptime { for (info.@"struct".decls) |decl| { if (decl.is_pub) @compileLog(decl.name); }}
