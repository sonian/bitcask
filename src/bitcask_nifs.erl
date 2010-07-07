%% -------------------------------------------------------------------
%%
%% bitcask: Eric Brewer-inspired key/value store
%%
%% Copyright (c) 2010 Basho Technologies, Inc. All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
-module(bitcask_nifs).
-author('Dave Smith <dizzyd@basho.com>').
-author('Justin Sheehy <justin@basho.com>').

-export([init/0,
         keydir_new/0, keydir_new/1,
         keydir_mark_ready/1,
         keydir_put/6,
         keydir_get/2,
         keydir_remove/2, keydir_remove/4,
         keydir_copy/1,
         keydir_itr/1,
         keydir_itr_next/1,
         keydir_fold/3,
         keydir_info/1,
         keydir_release/1,
         create_file/1,
         set_osync/1,
         lock_acquire/2,
         lock_release/1,
         lock_readdata/1,
         lock_writedata/2]).

%% Internal use/debugging use only
-export([keydir_put_int/6, keydir_get_int/2]).

-on_load(init/0).

-include("bitcask.hrl").

-ifdef(PULSE).
-compile({parse_transform, pulse_instrument}).
-endif.

-ifdef(TEST).
-ifdef(EQC).
-include_lib("eqc/include/eqc.hrl").
-endif.
-compile(export_all).
-include_lib("eunit/include/eunit.hrl").
-endif.

init() ->
    case code:priv_dir(bitcask) of
        {error, bad_name} ->
            SoName = filename:join("../priv", bitcask);
        Dir ->
            SoName = filename:join(Dir, bitcask)
    end,
    erlang:load_nif(SoName, 0).

keydir_new() ->
    "NIF library not loaded".

keydir_new(_Name) ->
    "NIF library not loaded".

keydir_mark_ready(_Ref) ->
    "NIF library not loaded".

keydir_put(Ref, Key, FileId, TotalSz, Offset, Tstamp)
  when is_integer(Offset)->
    keydir_put_int(Ref, Key, FileId, TotalSz, ext_to_int_offset(Offset),
                   Tstamp);
keydir_put(Ref, Key, FileId, TotalSz, Offset, Tstamp) ->
    keydir_put_int(Ref, Key, FileId, TotalSz, Offset, Tstamp).    

keydir_put_int(_Ref, _Key, _FileId, _TotalSz, _Offset, _Tstamp) ->
    "NIF library not loaded".

keydir_get(Ref, Key) ->
    case keydir_get_int(Ref, Key) of
        E when is_record(E, bitcask_entry) ->
            E#bitcask_entry{offset = int_to_ext_offset(E#bitcask_entry.offset)};
        Else ->
            Else
    end.

keydir_get_int(_Ref, _Key) ->
    "NIF library not loaded".

keydir_remove(_Ref, _Key) ->
    "NIF library not loaded".

keydir_remove(_Ref, _Key, _Tstamp, _FileId) ->
    "NIF library not loaded".

keydir_copy(_Ref) ->
    "NIF library not loaded".

keydir_itr(_Ref) ->
    "NIF library not loaded".

keydir_itr_next(_Itr) ->
    "NIF library not loaded".

keydir_fold(Ref, Fun, Acc0) ->
    case keydir_itr(Ref) of
        ok ->
            keydir_fold_cont(keydir_itr_next(Ref), Ref, Fun, Acc0);
        {error, Reason} ->
            {error, Reason}
    end.

keydir_info(_Ref) ->
    "NIF library not loaded".

keydir_release(_Ref) ->
    "NIF library not loaded".

create_file(_Filename) ->
    "NIF library not loaded".

set_osync(_Filehandle) ->
    "NIF library not loaded".

lock_acquire(_Filename, _IsWriteLock) ->
    "NIF library not loaded".

lock_release(_Ref) ->
    "NIF library not loaded".

lock_readdata(_Ref) ->
    "NIF library not loaded".

lock_writedata(_Ref, _Data) ->
    "NIF library not loaded".

%% ===================================================================
%% Internal functions
%% ===================================================================

keydir_fold_cont(not_found, _Ref, _Fun, Acc0) ->
    Acc0;
keydir_fold_cont(Curr, Ref, Fun, Acc0) ->
    Acc = Fun(Curr, Acc0),
    keydir_fold_cont(keydir_itr_next(Ref), Ref, Fun, Acc).

%% Note: 18446744073709551616 = 2^64

ext_to_int_offset(Offset) when Offset <  18446744073709551616,
                               Offset >= 0 ->
    {(Offset band 16#FFFFFFFF00000000) bsr 32, Offset band 16#00000000FFFFFFFF}.

int_to_ext_offset({High32, Low32}) ->
    (High32 bsl 32) bor Low32.

%% ===================================================================
%% EUnit tests
%% ===================================================================
-ifdef(TEST).

keydir_basic_test() ->
    {ok, Ref} = keydir_new(),
    ok = keydir_put(Ref, <<"abc">>, 0, 1234, 0, 1),

    {1, 3, [{0, 1, 1, 1234, 1234}]} = keydir_info(Ref),

    E = keydir_get(Ref, <<"abc">>),
    0 = E#bitcask_entry.file_id,
    1234 = E#bitcask_entry.total_sz,
    0 = E#bitcask_entry.offset,
    1 = E#bitcask_entry.tstamp,

    already_exists = keydir_put(Ref, <<"abc">>, 0, 1234, 0, 0),

    ok = keydir_remove(Ref, <<"abc">>),
    not_found = keydir_get(Ref, <<"abc">>).

keydir_itr_test() ->
    {ok, Ref} = keydir_new(),
    ok = keydir_put(Ref, <<"abc">>, 0, 1234, 0, 1),
    ok = keydir_put(Ref, <<"def">>, 0, 4567, 1234, 2),
    ok = keydir_put(Ref, <<"hij">>, 1, 7890, 0, 3),

    {3, 9, _} = keydir_info(Ref),

    List = keydir_fold(Ref, fun(E, Acc) -> [ E | Acc] end, []),
    3 = length(List),
    true = lists:keymember(<<"abc">>, #bitcask_entry.key, List),
    true = lists:keymember(<<"def">>, #bitcask_entry.key, List),
    true = lists:keymember(<<"hij">>, #bitcask_entry.key, List).

keydir_copy_test() ->
    {ok, Ref1} = keydir_new(),
    ok = keydir_put(Ref1, <<"abc">>, 0, 1234, 0, 1),
    ok = keydir_put(Ref1, <<"def">>, 0, 4567, 1234, 2),
    ok = keydir_put(Ref1, <<"hij">>, 1, 7890, 0, 3),

    {ok, Ref2} = keydir_copy(Ref1),
    #bitcask_entry { key = <<"abc">>} = keydir_get(Ref2, <<"abc">>).

keydir_named_test() ->
    {not_ready, Ref} = keydir_new("k1"),
    ok = keydir_put(Ref, <<"abc">>, 0, 1234, 0, 1),
    keydir_mark_ready(Ref),

    {ready, Ref2} = keydir_new("k1"),
    #bitcask_entry { key = <<"abc">> } = keydir_get(Ref2, <<"abc">>).

keydir_named_not_ready_test() ->
    {not_ready, Ref} = keydir_new("k2"),
    ok = keydir_put(Ref, <<"abc">>, 0, 1234, 0, 1),

    {error, not_ready} = keydir_new("k2").

keydir_named_noitr_test() ->
    {not_ready, Ref} = keydir_new("k3"),
    {error, iteration_not_permitted} = keydir_itr(Ref).


create_file_test() ->
    Fname = "/tmp/bitcask_nifs.createfile.test",
    file:delete(Fname),
    true = create_file(Fname),
    false = create_file(Fname).

-ifdef(EQC).

-define(POW_2(N), trunc(math:pow(2, N))).

-define(QC_OUT(P),
        eqc:on_output(fun(Str, Args) -> io:format(user, Str, Args) end, P)).

g_uint32() ->
    choose(0, ?POW_2(31)).

g_uint64() ->
    choose(0, ?POW_2(62)).

g_entry() ->
    #bitcask_entry{ key = non_empty(binary()),
                    file_id = g_uint32(),
                    total_sz = g_uint32(),
                    offset = g_uint64(),
                    tstamp = g_uint32() }.

keydir_get_put_prop() ->
    ?FORALL(E, g_entry(),
            begin
                {ok, Ref} = keydir_new(),

                ok = keydir_put(Ref, E#bitcask_entry.key, E#bitcask_entry.file_id,
                                E#bitcask_entry.total_sz, E#bitcask_entry.offset,
                                E#bitcask_entry.tstamp),

                E2 = keydir_get(Ref, E#bitcask_entry.key),
                keydir_release(Ref),
                ?assertEqual(E, E2),
                true
            end).

keydir_get_put_test_() ->
    {timeout, 60, fun() -> eqc:quickcheck(?QC_OUT(keydir_get_put_prop())) end}.

-endif.

-endif.
