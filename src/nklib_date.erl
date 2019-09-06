%% -------------------------------------------------------------------
%%
%% Copyright (c) 2019 Carlos Gonzalez Florido.  All Rights Reserved.
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

%% @doc NetComposer Standard Library
-module(nklib_date).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([epoch/1, now_hex/1, epoch_to_hex/2, now_3339/1]).
-export([to_3339/2, to_epoch/2, is_3339/1]).
-export([age/1]).
-export_type([epoch_unit/0, epoch/1]).

-type epoch_unit() :: secs | msecs | usecs.
-type epoch(_Unit) :: pos_integer().

-include("nklib.hrl").

-compile(inline).

%% ===================================================================
%% Public
%% ===================================================================

%% @doc Get current epoch time
-spec epoch(epoch_unit()) ->
    integer().

epoch(secs) ->
    epoch(usecs) div 1000000;

epoch(msecs) ->
    epoch(usecs) div 1000;

epoch(usecs) ->
    {N1, N2, N3} = os:timestamp(),
    (N1 * 1000000 + N2) * 1000000 + N3.


%% @doc Get current epoch in binary for sorting, in hex format
%% See epoch_to_hex/2
-spec now_hex(epoch_unit()) ->
    binary().

now_hex(Unit) ->
    epoch_to_hex(epoch(Unit), Unit).


%% @doc Get current epoch in binary for sorting, in hex format
%% For secs:  10 bytes
%% For msecs: 12 bytes
%% For usecs: 14 byes
%% It will never wrap, see epoch_to_hex_test/0

epoch_to_hex(Epoch, Unit) ->
    Hex = nklib_util:hex(binary:encode_unsigned(Epoch)),
    Size = case Unit of
        secs -> 10;
        msecs -> 12;
        usecs -> 14
    end,
    case byte_size(Hex) of
        Size ->
            Hex;
        HexSize ->
            BinPad = binary:copy(<<"0">>, Size - HexSize),
            <<BinPad/binary, Hex/binary>>
    end.


%% @doc Get current epoch time, using the cached pattern
%% The normal approach get_date + convert_to_3339 takes about 100K-140K/s (usecs-secs)
%% This approach taking a second-resolution cache takes about 1M-2M/s (usecs-secs)
-spec now_3339(epoch_unit()) ->
    binary().

now_3339(secs) ->
    Secs = epoch(secs),
    case ets:lookup(nklib_date, date) of
        [{date, Secs, Secs3339}] ->
            <<Secs3339/binary, $Z>>;
        _ ->
            {ok, Date} = to_3339(Secs, secs),
            <<Date2:19/binary, _/binary>> = Date,
            ets:insert(nklib_date, {date, Secs, Date2}),
            Date
    end;

now_3339(msecs) ->
    Now = epoch(msecs),
    Secs = Now div 1000,
    case ets:lookup(nklib_date, date) of
        [{date, Secs, Secs3339}] ->
            Rem1 = Now rem 1000,
            Rem2 = nklib_util:lpad(Rem1, 3, $0),
            <<Secs3339/binary, $., Rem2/binary, "000Z">>;
        _ ->
            {ok, Date} = to_3339(Now, msecs),
            <<Date2:19/binary, _/binary>> = Date,
            ets:insert(nklib_date, {date, Secs, Date2}),
            Date
    end;

now_3339(usecs) ->
    Now = epoch(usecs),
    Secs = Now div 1000000,
    case ets:lookup(nklib_date, date) of
        [{date, Secs, Secs3339}] ->
            Rem1 = Now rem 1000000,
            Rem2 = nklib_util:lpad(Rem1, 6, $0),
            <<Secs3339/binary, $., Rem2/binary, $Z>>;
        _ ->
            {ok, Date} = to_3339(Now, usecs),
            <<Date2:19/binary, _/binary>> = Date,
            ets:insert(nklib_date, {date, Secs, Date2}),
            Date
    end.



%% @doc Converts an incoming epoch or rfc3339 to normalized rfc3339
-spec to_3339(integer()|binary()|string(), epoch_unit()) ->
    {ok, binary()} | {error, term()}.

to_3339(Epoch, Unit) when is_integer(Epoch) ->
    rfc3339:format(Epoch, to_erlang_unit(Unit));

to_3339(Date, Unit) when is_binary(Date); is_list(Date) ->
    Date2 = norm_date(to_bin(Date)),
    case rfc3339:to_time(Date2, to_erlang_unit(Unit)) of
        {ok, Time} when is_integer(Time) ->
            to_3339(Time, Unit);
        {error, Error} ->
            {error, Error}
    end.


%% @doc Converts an incoming epoch or rfc3339 to normalized epoch
-spec to_epoch(integer()|binary()|list(), epoch_unit()) ->
    {ok, integer()} | {error, term()}.

to_epoch(Epoch, Unit) when is_integer(Epoch) ->
    case epoch_unit(Epoch) of
        Unit ->
            {ok, Epoch};
        secs when Unit==msecs ->
            {ok, Epoch * 1000};
        secs when Unit==usecs ->
            {ok, Epoch * 1000000};
        msecs when Unit==secs ->
            {ok, Epoch div 1000};
        msecs when Unit==usecs ->
            {ok, Epoch * 1000};
        usecs when Unit==secs ->
            {ok, Epoch div 1000000};
        usecs when Unit==msecs ->
            {ok, Epoch div 1000}
    end;

to_epoch(Date, Unit) when is_binary(Date); is_list(Date) ->
    rfc3339:to_time(to_bin(Date), to_erlang_unit(Unit)).


%% @doc Quick 3339 parser (only for Z timezone)
%% Doesn't check on invalid dates
-spec is_3339(binary()|string()) ->
    {true, {calendar:datetime(), float(), epoch_unit()}} | false.

is_3339(Val) ->
    case to_bin(Val) of
        <<
            Y1, Y2, Y3, Y4, $- , M1, M2, $-, D1, D2, $T,
            H1, H2, $:, Mi1, Mi2, $:, S1, S2, Rest/binary
        >> when
            Y1>=$0, Y1=<$9, Y2>=$0, Y2=<$9, Y3>=$0, Y3=<$9, Y4>=$0, Y4=<$9,
            M1>=$0, M1=<$9, M2>=$0, M2=<$9, D1>=$0, D1=<$9, D2>=$0, D2=<$9,
            H1>=$0, H1=<$9, H2>=$0, H2=<$9, Mi1>=$0, Mi1=<$9, Mi2>=$0, Mi2=<$9,
            S1>=$0, S1=<$9, S2>=$0, S2=<$9 ->
            Y = (Y1-$0)*1000 + (Y2-$0)*100 + (Y3-$0)*10 + (Y4-$0),
            M = (M1-$0)*10 + (M2-$0),
            D = (D1-$0)*10 + (D2-$0),
            H = (H1-$0)*10 + (H2-$0),
            Mi = (Mi1-$0)*10 + (Mi2-$0),
            S = (S1-$0)*10 + (S2-$0),
            case binary:split(Rest, <<"Z">>) of
                [<<>>, <<>>] ->
                    {true, {{{Y, M, D}, {H, Mi, S}}, 0.0, secs}};
                [<<$., Dec/binary>>, <<>>] ->
                    case catch binary_to_float(<<"0.", Dec/binary>>) of
                        {'EXIT', _} ->
                            error;
                        Dec2 ->
                            Unit = case byte_size(Dec) < 4 of
                                true -> msecs;
                                false -> usecs
                            end,
                            {true, {{{Y, M, D}, {H, Mi, S}}, Dec2, Unit}}
                    end;
                _ ->
                    false
            end;
        _ ->
            false
    end.


%% @private
epoch_unit(Val) ->
    case byte_size(integer_to_binary(abs(Val))) of
        Size when Size =< 10 ->
            secs;
        Size when Size >= 11, Size =< 13 ->
            msecs;
        _ ->
            usecs
    end.


%% @private
to_erlang_unit(Unit) ->
    case Unit of
        secs -> second;
        msecs -> millisecond;
        usecs -> microsecond
    end.


%% @private
norm_date(Val) ->
    case Val of
        <<_Y:4/binary>> ->
            <<Val/binary, "-01-01T00:00:00Z">>;
        <<_Y:4/binary, $-, _M:2/binary>> ->
            <<Val/binary, "-01T00:00:00Z">>;
        <<_Y:4/binary, $-, _M:2/binary, $-, _D:2/binary>> ->
            <<Val/binary, "T00:00:00Z">>;
        _ ->
            Val
    end.

%% @doc
age(Secs1) when is_integer(Secs1) ->
    Secs2 = epoch(secs),
    {{Y2, M2, D2}, _} = calendar:now_to_local_time({0, Secs2, 0}),
    {{Y1, M1, D1}, _} = calendar:now_to_local_time({0, Secs1, 0}),
    Years1 = Y2 - Y1,
    if
        M2 >= M1, D2 >= D1 ->
            {ok, Years1+1};
        true ->
            {ok, Years1}
    end;

age(Date) ->
    case to_epoch(Date, secs) of
        {ok, Secs1} ->
            age(Secs1);
        {error, Error} ->
            {error, Error}
    end.


%% @private
to_bin(K) when is_binary(K) -> K;
to_bin(K) -> nklib_util:to_binary(K).





%% ===================================================================
%% EUnit tests
%% ===================================================================

%-define(TEST, 1).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").


dates_test() ->
    G1971 = nklib_util:gmt_to_timestamp({{1971, 1, 1}, {0,0,0}}),
    G1980 = nklib_util:gmt_to_timestamp({{1980, 1, 1}, {0,0,0}}),
    G2018 = nklib_util:gmt_to_timestamp({{2018, 1, 1}, {0,0,0}}),
    G2100 = nklib_util:gmt_to_timestamp({{2100, 1, 1}, {0,0,0}}),

    {ok, <<"1971-01-01T00:00:00Z">>} = to_3339(G1971, secs),
    {ok, <<"1971-01-01T00:00:00Z">>} = to_3339(G1971*1000, msecs),
    {ok, <<"1971-01-01T00:00:00Z">>} = to_3339(G1971*1000*1000, usecs),
    {ok, <<"1971-01-01T00:00:00.001000Z">>} = to_3339(G1971 * 1000 + 1, msecs),
    {ok, <<"1971-01-01T00:00:00.000001Z">>} = to_3339(G1971 * 1000 * 1000 + 1, usecs),

    {ok, <<"1980-01-01T00:00:00Z">>} = to_3339(G1980, secs),
    {ok, <<"1980-01-01T00:00:00.001000Z">>} = to_3339(G1980 * 1000 + 1, msecs),
    {ok, <<"1980-01-01T00:00:00.000001Z">>} = to_3339(G1980 * 1000 * 1000 + 1, usecs),

    {ok, <<"2018-01-01T00:00:00Z">>} = to_3339(G2018, secs),
    {ok, <<"2018-01-01T00:00:00.001000Z">>} = to_3339(G2018 * 1000 +  1, msecs),
    {ok, <<"2018-01-01T00:00:00.000001Z">>} = to_3339(G2018 * 1000 * 1000 + 1, usecs),

    {ok, <<"2100-01-01T00:00:00Z">>} = to_3339(G2100, secs),
    {ok, <<"2100-01-01T00:00:00.001000Z">>} = to_3339(G2100 * 1000 + 1, msecs),
    {ok, <<"2100-01-01T00:00:00.000001Z">>} = to_3339(G2100 * 1000 * 1000 + 1, usecs),

    {ok, <<"1980-01-01T00:00:00Z">>} = to_3339("1980", secs),
    {ok, <<"1980-02-01T00:00:00Z">>} = to_3339("1980-02", secs),
    {ok, <<"1980-02-03T00:00:00Z">>} = to_3339("1980-02-03", secs),

    {ok, <<"1980-01-01T00:00:00Z">>} = to_3339("1980-01-01T00:00:00Z", secs),
    {ok, <<"1980-01-01T00:00:00.001000Z">>} = to_3339("1980-01-01T00:00:00.001Z", msecs),
    {ok, <<"1980-01-01T00:00:00.000001Z">>} = to_3339("1980-01-01T00:00:00.000001Z", usecs),

    {true,{{{2015,6,30},{23,59,10}},0.0,secs}} = is_3339("2015-06-30T23:59:10Z"),
    false = is_3339("2015-06-30T23:59:10"),
    {true,{{{2015,6,30},{23,59,10}},0.1,msecs}} = is_3339("2015-06-30T23:59:10.1Z"),
    {true,{{{2015,6,30},{23,59,10}},0.01,msecs}} = is_3339("2015-06-30T23:59:10.01Z"),
    {true,{{{2015,6,30},{23,59,10}},0.001,msecs}} = is_3339("2015-06-30T23:59:10.001Z"),
    {true,{{{2015,6,30},{23,59,10}},0.0001,usecs}} = is_3339("2015-06-30T23:59:10.0001Z"),

    1435708750 = nklib_util:gmt_to_timestamp({{2015,6,30},{23,59,10}}),

    {ok,1435708750} = to_epoch(1435708750, secs),
    {ok,1435708750000} = to_epoch(1435708750, msecs),
    {ok,1435708750000000} = to_epoch(1435708750, usecs),

    {ok,1435708750} = to_epoch(1435708750000, secs),
    {ok,1435708750000} = to_epoch(1435708750000, msecs),
    {ok,1435708750000000} = to_epoch(1435708750000, usecs),

    {ok,1435708750} = to_epoch(1435708750000000, secs),
    {ok,1435708750000} = to_epoch(1435708750000000, msecs),
    {ok,1435708750000000} = to_epoch(1435708750000000, usecs),

    {ok,1435708750} = to_epoch("2015-06-30T23:59:10Z", secs),
    {ok,1435708750000} = to_epoch("2015-06-30T23:59:10Z", msecs),
    {ok,1435708750000000} = to_epoch("2015-06-30T23:59:10Z", usecs),

    {ok,1435708750} = to_epoch("2015-06-30T23:59:10.1Z", secs),
    {ok,1435708750100} = to_epoch("2015-06-30T23:59:10.1Z", msecs),
    {ok,1435708750100000} = to_epoch("2015-06-30T23:59:10.1Z", usecs),

    {ok,1435708750} = to_epoch("2015-06-30T23:59:10.01Z", secs),
    {ok,1435708750010} = to_epoch("2015-06-30T23:59:10.01Z", msecs),
    {ok,1435708750010000} = to_epoch("2015-06-30T23:59:10.01Z", usecs),
    ok.

epoch_to_hex_test() ->
    <<"0000000001">> = epoch_to_hex(1, secs),
    <<"0012cea600">> = epoch_to_hex(element(2, to_epoch("1980-01-01T00:00:00Z", secs)), secs),
    <<"005c2aad80">> = epoch_to_hex(element(2, to_epoch("2019-01-01T00:00:00Z", secs)), secs),
    <<"01b09e1900">> = epoch_to_hex(element(2, to_epoch("2200-01-01T00:00:00Z", secs)), secs),
    <<"0eea4f0300">> = epoch_to_hex(element(2, to_epoch("4000-01-01T00:00:00Z", secs)), secs),

    <<"000000000001">> = epoch_to_hex(1, msecs),
    <<"004977387000">> = epoch_to_hex(element(2, to_epoch("1980-01-01T00:00:00Z", msecs)), msecs),
    <<"016806b5bc00">> = epoch_to_hex(element(2, to_epoch("2019-01-01T00:00:00Z", msecs)), msecs),
    <<"0699e991a800">> = epoch_to_hex(element(2, to_epoch("2200-01-01T00:00:00Z", msecs)), msecs),
    <<"3a4344a3b800">> = epoch_to_hex(element(2, to_epoch("4000-01-01T00:00:00Z", msecs)), msecs),

    <<"00000000000001">> = epoch_to_hex(1, usecs),
    <<"011ef9b4758000">> = epoch_to_hex(element(2, to_epoch("1980-01-01T00:00:00Z", usecs)), usecs),
    <<"057e5a35e66000">> = epoch_to_hex(element(2, to_epoch("2019-01-01T00:00:00Z", usecs)), usecs),
    <<"19c93860f84000">> = epoch_to_hex(element(2, to_epoch("2200-01-01T00:00:00Z", usecs)), usecs),
    <<"e396c41f86c000">> = epoch_to_hex(element(2, to_epoch("4000-01-01T00:00:00Z", usecs)), usecs),
    ok.

-endif.




