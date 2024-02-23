const std = @import("std");
const c_translation = @import("std").zig.c_translation;
const cast = c_translation.cast;
const sizeof = c_translation.sizeof;
const MacroArithmetic = c_translation.MacroArithmetic;
pub export fn terminal_size(arg_fd: value) value {
    const fd = arg_fd;
    // init
    const caml_local_roots_ptr: [*c][*c]struct_caml__roots_block = &(caml_state).*.local_roots;
    const caml__frame: [*c]struct_caml__roots_block = caml_local_roots_ptr.*;
    // Arg1
    var caml__roots_fd: struct_caml__roots_block = undefined;
    caml__roots_fd.next = caml_local_roots_ptr.*;
    caml_local_roots_ptr.* = &caml__roots_fd;
    caml__roots_fd.nitems = 1;
    caml__roots_fd.ntables = 1;
    //local1
    var result: value = Val_unit;
    var caml__roots_result: struct_caml__roots_block = undefined;

    caml__roots_result.next = caml_local_roots_ptr.*;
    caml_local_roots_ptr.* = &caml__roots_result;
    caml__roots_result.nitems = 1;
    caml__roots_result.ntables = 1;
    caml__roots_result.tables[0] = &result;
    result = caml_alloc_tuple(2);
    var size: std.os.linux.winsize = .{ .ws_col = 0, .ws_row = 0, .ws_xpixel = 0, .ws_ypixel = 0 };
    _ = std.os.linux.ioctl(Int_val(fd), std.os.linux.T.IOCGWINSZ, @intFromPtr(&size));
    caml_modify(&@as([*c]volatile value, result)[0], Val_int(size.ws_col));
    caml_modify(&@as([*c]volatile value, result)[1], Val_int(size.ws_row));
    caml_local_roots_ptr.* = caml__frame;
    return result;
}
pub const asize_t = usize;
pub const intnat = c_long;
pub const uintnat = c_ulong;
pub const backtrace_slot = ?*anyopaque;
pub const value = intnat;
pub const header_t = uintnat;
pub const reserved_t = header_t;
pub const mlsize_t = uintnat;
pub const tag_t = c_uint;
pub const color_t = uintnat;
pub const mark_t = uintnat;
pub const value_ptr = [*c]volatile value;
pub const opcode_t = i32;
pub const code_t = [*c]opcode_t;
pub const extra_params_area = [64]value;
pub const struct_stack_info = opaque {};
pub const struct_c_stack_link = opaque {};
pub const struct_caml_minor_tables = opaque {};
pub const struct_mark_stack = opaque {};

pub const struct_caml__roots_block = extern struct {
    next: [*c]struct_caml__roots_block,
    ntables: intnat,
    nitems: intnat,
    tables: [5][*c]value,
};
pub const struct_caml_ephe_info = opaque {};
pub const struct_caml_final_info = opaque {};
pub const struct_caml_heap_state = opaque {};
pub const struct_caml_extern_state = opaque {};
pub const struct_caml_intern_state = opaque {};
pub const struct_caml_exception_context = opaque {};

pub const caml_domain_state = extern struct {
    young_limit: ?*anyopaque align(8), // _Atomic(uintnat)
    young_ptr: [*c]value align(8),
    young_start: [*c]value align(8),
    young_end: [*c]value align(8),
    young_trigger: [*c]value align(8),
    current_stack: ?*struct_stack_info align(8),
    exn_handler: ?*anyopaque align(8),
    action_pending: c_int align(8),
    c_stack: ?*struct_c_stack_link align(8),
    stack_cache: [*c]?*struct_stack_info align(8),
    gc_regs_buckets: [*c]value align(8),
    gc_regs: [*c]value align(8),
    minor_tables: ?*struct_caml_minor_tables align(8),
    mark_stack: ?*struct_mark_stack align(8),
    marking_done: uintnat align(8),
    sweeping_done: uintnat align(8),
    allocated_words: uintnat align(8),
    swept_words: uintnat align(8),
    major_slice_epoch: uintnat align(8),
    local_roots: [*c]struct_caml__roots_block align(8),
    ephe_info: ?*struct_caml_ephe_info align(8),
    final_info: ?*struct_caml_final_info align(8),
    backtrace_pos: intnat align(8),
    backtrace_active: intnat align(8),
    backtrace_buffer: [*c]backtrace_slot align(8),
    backtrace_last_exn: value align(8),
    compare_unordered: intnat align(8),
    oo_next_id_local: uintnat align(8),
    requested_major_slice: uintnat align(8),
    requested_global_major_slice: uintnat align(8),
    requested_minor_gc: uintnat align(8),
    requested_external_interrupt: ?*anyopaque align(8), // _Atomic(uintnat)
    parser_trace: c_int align(8),
    minor_heap_wsz: asize_t align(8),
    shared_heap: ?*struct_caml_heap_state align(8),
    id: c_int align(8),
    unique_id: c_int align(8),
    dls_root: value align(8),
    extra_heap_resources: f64 align(8),
    extra_heap_resources_minor: f64 align(8),
    dependent_size: uintnat align(8),
    dependent_allocated: uintnat align(8),
    slice_target: intnat align(8),
    slice_budget: intnat align(8),
    major_work_done_between_slices: intnat align(8),
    extern_state: ?*struct_caml_extern_state align(8),
    intern_state: ?*struct_caml_intern_state align(8),
    stat_minor_words: uintnat align(8),
    stat_promoted_words: uintnat align(8),
    stat_major_words: uintnat align(8),
    stat_forced_major_collections: intnat align(8),
    stat_blocks_marked: uintnat align(8),
    inside_stw_handler: c_int align(8),
    trap_sp_off: intnat align(8),
    trap_barrier_off: intnat align(8),
    trap_barrier_block: i64 align(8),
    external_raise: ?*struct_caml_exception_context align(8),
    extra_params: extra_params_area align(8),
};
pub const Domain_state_num_fields: c_int = 58;
pub extern threadlocal var caml_state: [*c]caml_domain_state;
pub extern fn caml_bad_caml_state() noreturn;
pub extern fn caml_get_public_method(obj: value, tag: value) value;
pub fn Val_ptr(arg_p: ?*anyopaque) callconv(.C) value {
    const p = arg_p;
    _ = @as(c_int, 0);
    return @as(value, @intCast(@intFromPtr(p))) + @as(value, @bitCast(@as(c_long, @as(c_int, 1))));
}
pub fn Ptr_val(arg_val: value) callconv(.C) ?*anyopaque {
    const val = arg_val;
    _ = @as(c_int, 0);
    return @as(?*anyopaque, @ptrFromInt(val - @as(value, @bitCast(@as(c_long, @as(c_int, 1))))));
}
pub extern fn caml_hash_variant(tag: [*c]const u8) value;
pub extern fn caml_string_length(value) mlsize_t;
pub extern fn caml_string_is_c_safe(value) c_int;
pub extern fn caml_array_length(value) mlsize_t;
pub extern fn caml_is_double_array(value) c_int;
pub const struct_custom_operations = opaque {};
pub extern fn caml_atom(tag_t) value;
pub extern fn caml_set_oo_id(obj: value) value;
pub extern fn caml_alloc(mlsize_t, tag_t) value;
pub extern fn caml_alloc_1(tag_t, value) value;
pub extern fn caml_alloc_2(tag_t, value, value) value;
pub extern fn caml_alloc_3(tag_t, value, value, value) value;
pub extern fn caml_alloc_4(tag_t, value, value, value, value) value;
pub extern fn caml_alloc_5(tag_t, value, value, value, value, value) value;
pub extern fn caml_alloc_6(tag_t, value, value, value, value, value, value) value;
pub extern fn caml_alloc_7(tag_t, value, value, value, value, value, value, value) value;
pub extern fn caml_alloc_8(tag_t, value, value, value, value, value, value, value, value) value;
pub extern fn caml_alloc_9(tag_t, value, value, value, value, value, value, value, value, value) value;
pub extern fn caml_alloc_small(mlsize_t, tag_t) value;
pub extern fn caml_alloc_shr_check_gc(mlsize_t, tag_t) value;
pub extern fn caml_alloc_tuple(mlsize_t) value;
pub extern fn caml_alloc_float_array(len: mlsize_t) value;
pub extern fn caml_alloc_string(len: mlsize_t) value;
pub extern fn caml_alloc_initialized_string(len: mlsize_t, [*c]const u8) value;
pub extern fn caml_copy_string([*c]const u8) value;
pub extern fn caml_copy_string_array([*c]const [*c]const u8) value;
pub extern fn caml_copy_double(f64) value;
pub extern fn caml_copy_int32(i32) value;
pub extern fn caml_copy_int64(i64) value;
pub extern fn caml_copy_nativeint(intnat) value;
pub extern fn caml_alloc_array(funct: ?*const fn ([*c]const u8) callconv(.C) value, array: [*c]const [*c]const u8) value;
pub extern fn caml_alloc_sprintf(format: [*c]const u8, ...) value;
pub extern fn caml_alloc_some(value) value;
pub const final_fun = ?*const fn (value) callconv(.C) void;
pub extern fn caml_alloc_final(mlsize_t, final_fun, mlsize_t, mlsize_t) value;
pub extern fn caml_convert_flag_list(value, [*c]const c_int) c_int;
pub fn caml_alloc_unboxed(arg_arg: value) callconv(.C) value {
    const arg = arg_arg;
    return arg;
}
pub fn caml_alloc_boxed(arg_arg: value) callconv(.C) value {
    const arg = arg_arg;
    const result: value = caml_alloc_small(@as(mlsize_t, @bitCast(@as(c_long, @as(c_int, 1)))), @as(tag_t, @bitCast(@as(c_int, 0))));
    @as([*c]volatile value, @ptrFromInt(result))[@as(c_uint, @intCast(@as(c_int, 0)))] = arg;
    return result;
}
pub fn caml_field_unboxed(arg_arg: value) callconv(.C) value {
    const arg = arg_arg;
    return arg;
}
pub fn caml_field_boxed(arg_arg: value) callconv(.C) value {
    const arg = arg_arg;
    return @as([*c]volatile value, @ptrFromInt(arg))[@as(c_uint, @intCast(@as(c_int, 0)))];
}
pub extern fn caml_enter_blocking_section() void;
pub extern fn caml_enter_blocking_section_no_pending() void;
pub extern fn caml_leave_blocking_section() void;
pub extern fn caml_process_pending_actions() void;
pub extern fn caml_process_pending_actions_exn() value;
pub extern fn caml_check_pending_actions() c_int;
pub extern fn caml_alloc_shr(wosize: mlsize_t, tag_t) value;
pub extern fn caml_alloc_shr_noexc(wosize: mlsize_t, tag_t) value;
pub extern fn caml_alloc_shr_reserved(mlsize_t, tag_t, reserved_t) value;
pub extern fn caml_adjust_gc_speed(mlsize_t, mlsize_t) void;
pub extern fn caml_adjust_minor_gc_speed(mlsize_t, mlsize_t) void;
pub extern fn caml_alloc_dependent_memory(bsz: mlsize_t) void;
pub extern fn caml_free_dependent_memory(bsz: mlsize_t) void;
pub extern fn caml_modify([*c]volatile value, value) void;
pub extern fn caml_initialize([*c]volatile value, value) void;
pub extern fn caml_atomic_cas_field(value, intnat, value, value) c_int;
pub extern fn caml_check_urgent_gc(value) value;
pub const caml_stat_block = ?*anyopaque;
pub extern fn caml_stat_alloc(asize_t) caml_stat_block;
pub extern fn caml_stat_alloc_noexc(asize_t) caml_stat_block;
pub extern fn caml_stat_alloc_aligned(asize_t, modulo: c_int, [*c]caml_stat_block) ?*anyopaque;
pub extern fn caml_stat_alloc_aligned_noexc(asize_t, modulo: c_int, [*c]caml_stat_block) ?*anyopaque;
pub extern fn caml_stat_calloc_noexc(asize_t, asize_t) caml_stat_block;
pub extern fn caml_stat_free(caml_stat_block) void;
pub extern fn caml_stat_resize(caml_stat_block, asize_t) caml_stat_block;
pub extern fn caml_stat_resize_noexc(caml_stat_block, asize_t) caml_stat_block;
pub const caml_stat_string = [*c]u8;
pub extern fn caml_stat_strdup(s: [*c]const u8) caml_stat_string;
pub extern fn caml_stat_strdup_noexc(s: [*c]const u8) caml_stat_string;
pub extern fn caml_stat_strconcat(n: c_int, ...) caml_stat_string;
pub extern fn caml_register_global_root([*c]value) void;
pub extern fn caml_remove_global_root([*c]value) void;
pub extern fn caml_register_generational_global_root([*c]value) void;
pub extern fn caml_remove_generational_global_root([*c]value) void;
pub extern fn caml_modify_generational_global_root(r: [*c]value, newval: value) void;

pub inline fn Is_long(x: anytype) @TypeOf((x & @as(c_int, 1)) != @as(c_int, 0)) {
    return (x & @as(c_int, 1)) != @as(c_int, 0);
}
pub inline fn Is_block(x: anytype) @TypeOf((x & @as(c_int, 1)) == @as(c_int, 0)) {
    return (x & @as(c_int, 1)) == @as(c_int, 0);
}
pub inline fn Val_long(x: anytype) @TypeOf(cast(intnat, cast(uintnat, x) << @as(c_int, 1)) + @as(c_int, 1)) {
    return cast(intnat, cast(uintnat, x) << @as(c_int, 1)) + @as(c_int, 1);
}
pub inline fn Long_val(x: anytype) @TypeOf(x >> @as(c_int, 1)) {
    return x >> @as(c_int, 1);
}
pub const Max_long = (cast(intnat, @as(c_int, 1)) << ((@as(c_int, 8) * sizeof(value)) - @as(c_int, 2))) - @as(c_int, 1);
pub const Min_long = -(cast(intnat, @as(c_int, 1)) << ((@as(c_int, 8) * sizeof(value)) - @as(c_int, 2)));

pub inline fn Val_int(x: anytype) @TypeOf(Val_long(x)) {
    return Val_long(x);
}
pub inline fn Int_val(x: anytype) c_int {
    return cast(c_int, Long_val(x));
}
pub inline fn Unsigned_long_val(x: anytype) @TypeOf(cast(uintnat, x) >> @as(c_int, 1)) {
    return cast(uintnat, x) >> @as(c_int, 1);
}
pub inline fn Unsigned_int_val(x: anytype) c_int {
    return cast(c_int, Unsigned_long_val(x));
}
pub inline fn Make_exception_result(v: anytype) @TypeOf(v | @as(c_int, 2)) {
    return v | @as(c_int, 2);
}
pub inline fn Is_exception_result(v: anytype) @TypeOf((v & @as(c_int, 3)) == @as(c_int, 2)) {
    return (v & @as(c_int, 3)) == @as(c_int, 2);
}
pub inline fn Extract_exception(v: anytype) @TypeOf(v & ~@as(c_int, 3)) {
    return v & ~@as(c_int, 3);
}
pub const CHAR_BIT = @as(c_int, 8);
pub const HEADER_BITS = sizeof(header_t) * CHAR_BIT;
pub const HEADER_TAG_BITS = @as(c_int, 8);
pub const HEADER_TAG_MASK = (@as(c_ulonglong, 1) << HEADER_TAG_BITS) - @as(c_ulonglong, 1);
pub const HEADER_COLOR_BITS = @as(c_int, 2);
pub const HEADER_COLOR_SHIFT = HEADER_TAG_BITS;
pub const HEADER_COLOR_MASK = ((@as(c_ulonglong, 1) << HEADER_COLOR_BITS) - @as(c_ulonglong, 1)) << HEADER_COLOR_SHIFT;
pub const HEADER_RESERVED_BITS = @as(c_int, 0);
pub const HEADER_WOSIZE_BITS = ((HEADER_BITS - HEADER_TAG_BITS) - HEADER_COLOR_BITS) - HEADER_RESERVED_BITS;
pub const HEADER_WOSIZE_SHIFT = HEADER_COLOR_SHIFT + HEADER_COLOR_BITS;
pub const HEADER_WOSIZE_MASK = ((@as(c_ulonglong, 1) << HEADER_WOSIZE_BITS) - @as(c_ulonglong, 1)) << HEADER_WOSIZE_SHIFT;
pub inline fn Tag_hd(hd: anytype) tag_t {
    return cast(tag_t, hd & HEADER_TAG_MASK);
}
pub inline fn Hd_with_tag(hd: anytype, tag: anytype) @TypeOf((hd & ~HEADER_TAG_MASK) | tag) {
    return (hd & ~HEADER_TAG_MASK) | tag;
}
pub inline fn Wosize_hd(hd: anytype) mlsize_t {
    return cast(mlsize_t, (hd & HEADER_WOSIZE_MASK) >> HEADER_WOSIZE_SHIFT);
}
pub inline fn Cleanhd_hd(hd: anytype) @TypeOf(cast(header_t, hd) & (HEADER_TAG_MASK | HEADER_WOSIZE_MASK)) {
    return cast(header_t, hd) & (HEADER_TAG_MASK | HEADER_WOSIZE_MASK);
}
pub inline fn Reserved_hd(hd: anytype) reserved_t {
    _ = @TypeOf(hd);
    return cast(reserved_t, @as(c_int, 0));
}
pub inline fn Hd_reserved(res: anytype) header_t {
    _ = @TypeOf(res);
    return cast(header_t, @as(c_int, 0));
}
pub inline fn Color_hd(hd: anytype) @TypeOf(hd & HEADER_COLOR_MASK) {
    return hd & HEADER_COLOR_MASK;
}
pub inline fn Hd_with_color(hd: anytype, color: anytype) @TypeOf((hd & ~HEADER_COLOR_MASK) | color) {
    return (hd & ~HEADER_COLOR_MASK) | color;
}
pub inline fn Hd_hp(hp: anytype) @TypeOf(cast([*c]header_t, hp).*) {
    return cast([*c]header_t, hp).*;
}
pub inline fn Hp_val(val: anytype) @TypeOf(cast([*c]header_t, val) - @as(c_int, 1)) {
    return cast([*c]header_t, val) - @as(c_int, 1);
}
pub inline fn Hp_op(op: anytype) @TypeOf(Hp_val(op)) {
    return Hp_val(op);
}
pub inline fn Hp_bp(bp: anytype) @TypeOf(Hp_val(bp)) {
    return Hp_val(bp);
}
pub inline fn Val_op(op: anytype) value {
    return cast(value, op);
}
pub inline fn Val_hp(hp: anytype) value {
    return cast(value, cast([*c]header_t, hp) + @as(c_int, 1));
}
pub inline fn Op_hp(hp: anytype) [*c]value {
    return cast([*c]value, Val_hp(hp));
}
pub inline fn Bp_hp(hp: anytype) [*c]u8 {
    return cast([*c]u8, Val_hp(hp));
}
pub const Num_tags = @as(c_ulonglong, 1) << HEADER_TAG_BITS;
pub const Max_wosize = (@as(c_ulonglong, 1) << HEADER_WOSIZE_BITS) - @as(c_ulonglong, 1);
pub inline fn Wosize_hp(hp: anytype) @TypeOf(Wosize_hd(Hd_hp(hp))) {
    return Wosize_hd(Hd_hp(hp));
}
pub inline fn Whsize_wosize(sz: anytype) @TypeOf(sz + @as(c_int, 1)) {
    return sz + @as(c_int, 1);
}
pub inline fn Wosize_whsize(sz: anytype) @TypeOf(sz - @as(c_int, 1)) {
    return sz - @as(c_int, 1);
}
pub inline fn Wosize_bhsize(sz: anytype) @TypeOf(MacroArithmetic.div(sz, sizeof(value)) - @as(c_int, 1)) {
    return MacroArithmetic.div(sz, sizeof(value)) - @as(c_int, 1);
}
pub inline fn Bsize_wsize(sz: anytype) @TypeOf(sz * sizeof(value)) {
    return sz * sizeof(value);
}
pub inline fn Wsize_bsize(sz: anytype) @TypeOf(MacroArithmetic.div(sz, sizeof(value))) {
    return MacroArithmetic.div(sz, sizeof(value));
}
pub inline fn Bhsize_wosize(sz: anytype) @TypeOf(Bsize_wsize(Whsize_wosize(sz))) {
    return Bsize_wsize(Whsize_wosize(sz));
}
pub inline fn Bhsize_bosize(sz: anytype) @TypeOf(sz + sizeof(header_t)) {
    return sz + sizeof(header_t);
}
pub inline fn Bosize_hd(hd: anytype) @TypeOf(Bsize_wsize(Wosize_hd(hd))) {
    return Bsize_wsize(Wosize_hd(hd));
}
pub inline fn Whsize_hp(hp: anytype) @TypeOf(Whsize_wosize(Wosize_hp(hp))) {
    return Whsize_wosize(Wosize_hp(hp));
}
pub inline fn Whsize_val(val: anytype) @TypeOf(Whsize_hp(Hp_val(val))) {
    return Whsize_hp(Hp_val(val));
}
pub inline fn Whsize_bp(bp: anytype) @TypeOf(Whsize_val(Val_bp(bp))) {
    return Whsize_val(Val_bp(bp));
}
pub inline fn Whsize_hd(hd: anytype) @TypeOf(Whsize_wosize(Wosize_hd(hd))) {
    return Whsize_wosize(Wosize_hd(hd));
}
pub inline fn Bhsize_hp(hp: anytype) @TypeOf(Bsize_wsize(Whsize_hp(hp))) {
    return Bsize_wsize(Whsize_hp(hp));
}
pub inline fn Bhsize_hd(hd: anytype) @TypeOf(Bsize_wsize(Whsize_hd(hd))) {
    return Bsize_wsize(Whsize_hd(hd));
}
pub const No_scan_tag = @as(c_int, 251);
pub inline fn Op_val(x: anytype) [*c]value {
    return cast([*c]value, x);
}
pub const Forward_tag = @as(c_int, 250);
pub const Infix_tag = @as(c_int, 249);
pub inline fn Infix_offset_hd(hd: anytype) @TypeOf(Bosize_hd(hd)) {
    return Bosize_hd(hd);
}
pub const Object_tag = @as(c_int, 248);
pub const Closure_tag = @as(c_int, 247);
pub inline fn Code_val(val: anytype) @TypeOf(cast([*c]code_t, val)[@as(usize, @intCast(@as(c_int, 0)))]) {
    return cast([*c]code_t, val)[@as(usize, @intCast(@as(c_int, 0)))];
}
pub inline fn Arity_closinfo(info: anytype) @TypeOf(cast(intnat, info) >> @as(c_int, 56)) {
    return cast(intnat, info) >> @as(c_int, 56);
}
pub inline fn Start_env_closinfo(info: anytype) @TypeOf((cast(uintnat, info) << @as(c_int, 8)) >> @as(c_int, 9)) {
    return (cast(uintnat, info) << @as(c_int, 8)) >> @as(c_int, 9);
}
pub inline fn Make_closinfo(arity: anytype, delta: anytype) @TypeOf(((cast(uintnat, arity) << @as(c_int, 56)) + (cast(uintnat, delta) << @as(c_int, 1))) + @as(c_int, 1)) {
    return ((cast(uintnat, arity) << @as(c_int, 56)) + (cast(uintnat, delta) << @as(c_int, 1))) + @as(c_int, 1);
}
pub const Lazy_tag = @as(c_int, 246);
pub const Cont_tag = @as(c_int, 245);
pub const Forcing_tag = @as(c_int, 244);
pub inline fn Bp_val(v: anytype) [*c]u8 {
    return cast([*c]u8, v);
}
pub inline fn Val_bp(p: anytype) value {
    return cast(value, p);
}
pub inline fn Byte(x: anytype, i: anytype) @TypeOf(cast([*c]u8, x)[@as(usize, @intCast(i))]) {
    return cast([*c]u8, x)[@as(usize, @intCast(i))];
}
pub inline fn Byte_u(x: anytype, i: anytype) @TypeOf(cast([*c]u8, x)[@as(usize, @intCast(i))]) {
    return cast([*c]u8, x)[@as(usize, @intCast(i))];
}
pub const Abstract_tag = @as(c_int, 251);
pub inline fn Data_abstract_val(v: anytype) ?*anyopaque {
    return cast(?*anyopaque, Op_val(v));
}
pub const String_tag = @as(c_int, 252);
pub inline fn Bytes_val(x: anytype) [*c]u8 {
    return cast([*c]u8, Bp_val(x));
}
pub const Double_tag = @as(c_int, 253);
pub const Double_wosize = MacroArithmetic.div(sizeof(f64), sizeof(value));
pub inline fn Double_val(v: anytype) @TypeOf(cast([*c]f64, v).*) {
    return cast([*c]f64, v).*;
}
pub const Double_array_tag = @as(c_int, 254);
pub inline fn Double_flat_field(v: anytype, i: anytype) @TypeOf(Double_val(cast(value, cast([*c]f64, v) + i))) {
    return Double_val(cast(value, cast([*c]f64, v) + i));
}
pub inline fn Double_array_field(v: anytype, i: anytype) @TypeOf(Double_flat_field(v, i)) {
    return Double_flat_field(v, i);
}
pub inline fn Double_field(v: anytype, i: anytype) @TypeOf(Double_flat_field(v, i)) {
    return Double_flat_field(v, i);
}
pub const Custom_tag = @as(c_int, 255);
pub inline fn Data_custom_val(v: anytype) ?*anyopaque {
    return cast(?*anyopaque, Op_val(v) + @as(c_int, 1));
}
pub inline fn Int32_val(v: anytype) @TypeOf(cast([*c]i32, Data_custom_val(v)).*) {
    return cast([*c]i32, Data_custom_val(v)).*;
}
pub inline fn Nativeint_val(v: anytype) @TypeOf(cast([*c]intnat, Data_custom_val(v)).*) {
    return cast([*c]intnat, Data_custom_val(v)).*;
}
pub inline fn Int64_val(v: anytype) @TypeOf(cast([*c]i64, Data_custom_val(v)).*) {
    return cast([*c]i64, Data_custom_val(v)).*;
}
pub inline fn Atom(tag: anytype) @TypeOf(caml_atom(tag)) {
    return caml_atom(tag);
}
pub inline fn Val_bool(x: anytype) @TypeOf(Val_int(x != @as(c_int, 0))) {
    return Val_int(x != @as(c_int, 0));
}
pub inline fn Bool_val(x: anytype) @TypeOf(Int_val(x)) {
    return Int_val(x);
}
pub const Val_false = Val_int(@as(c_int, 0));
pub const Val_true = Val_int(@as(c_int, 1));
pub inline fn Val_not(x: anytype) @TypeOf((Val_false + Val_true) - x) {
    return (Val_false + Val_true) - x;
}
pub const Val_unit = Val_int(@as(c_int, 0));
pub const Val_emptylist = Val_int(@as(c_int, 0));
pub const Tag_cons = @as(c_int, 0);
pub const Val_none = Val_int(@as(c_int, 0));
pub const Tag_some = @as(c_int, 0);
pub inline fn Is_none(v: anytype) @TypeOf(v == Val_none) {
    return v == Val_none;
}
pub inline fn Is_some(v: anytype) @TypeOf(Is_block(v)) {
    return Is_block(v);
}
pub inline fn Caml_out_of_heap_header_with_reserved(wosize: anytype, tag: anytype, reserved: anytype) @TypeOf(((cast(header_t, Hd_reserved(reserved)) + (cast(header_t, wosize) << HEADER_WOSIZE_SHIFT)) + (@as(c_int, 3) << HEADER_COLOR_SHIFT)) + cast(tag_t, tag)) {
    return ((cast(header_t, Hd_reserved(reserved)) + (cast(header_t, wosize) << HEADER_WOSIZE_SHIFT)) + (@as(c_int, 3) << HEADER_COLOR_SHIFT)) + cast(tag_t, tag);
}
pub inline fn Caml_out_of_heap_header(wosize: anytype, tag: anytype) @TypeOf(Caml_out_of_heap_header_with_reserved(wosize, tag, @as(c_int, 0))) {
    return Caml_out_of_heap_header_with_reserved(wosize, tag, @as(c_int, 0));
}
