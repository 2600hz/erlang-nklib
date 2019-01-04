%% -------------------------------------------------------------------
%%
%% Copyright (c) 2018 Carlos Gonzalez Florido.  All Rights Reserved.
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

%% @doc Common library utility functions
-module(nklib_parse_trans_vsn).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([parse_transform/2]).


%% ===================================================================
%% Public
%% ===================================================================

%% @doc Replaces do_fun/1 for a version compatible with erlang pre and post 21
parse_transform(Forms, _Opts) ->
    Forms2 = nklib_code:forms_replace_fun(do_try, 1,  make_try_fun(), Forms),
    Forms3 = nklib_code:forms_replace_fun(do_config_get, 1,  make_get_fun(), Forms2),
    Forms4 = nklib_code:forms_replace_fun(do_config_put, 2,  make_put_fun(), Forms3),
    Forms4.


%% @private
make_try_fun() ->
    Exp = case is_21() of
        true ->
            "
                do_try(Fun) ->
                    try Fun()
                catch
                    throw:Throw -> {exception, {throw, {Throw, []}}};
                    Class:Error:Trace -> {exception, {Class, {Error, Trace}}}
                end.
            ";
        false ->
            "
                do_try(Fun) ->
                    try Fun()
                catch
                    throw:Throw -> {exception, {throw, {Throw, []}}};
                    Class:Error -> {exception, {Class, {Error, erlang:get_stacktrace()}}}
                end.
            "
    end,
    {ok, Form} = nklib_code:expression(Exp),
    Form.


%% @private
make_get_fun() ->
    Exp = case is_21() of
        true ->
            "
                do_config_get(Key) ->
                    permanent_term:get(Key).
            ";
        false ->
            "
                do_config_get(Key) ->
                    nklib_config:get(nklib_trans_comp, Key).
            "
    end,
    {ok, Form} = nklib_code:expression(Exp),
    Form.


%% @private
make_put_fun() ->
    Exp = case is_21() of
        true ->
            "
                do_config_put(Key, Value) ->
                    permanent_term:get(Key, Value).
            ";
        false ->
            "
                do_config_put(Key, Value) ->
                    nklib_config:put(nklib_trans_comp, Key, Value).
            "
    end,
    {ok, Form} = nklib_code:expression(Exp),
    Form.


%% @private
is_21() ->
    erlang:system_info(otp_release) >= "21".