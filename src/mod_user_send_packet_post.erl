%%%----------------------------------------------------------------------

%%% File    : mod_user_send_packet_post.erl
%%% Author  : Dirk Moors <dirkmoors@gmail.com>
%%% Purpose : Forward sent (muc) messages
%%% Created : 22 Aug 2014 by Dirk Moors <dirkmoors@gmail.com>
%%%
%%%
%%% Copyright (C) 2014  Dirk Moors
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with this program; if not, write to the Free Software
%%% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
%%% 02111-1307 USA
%%%
%%%----------------------------------------------------------------------

-module(mod_user_send_packet_post).
-author('dirkmoors@gmail.com').

-behaviour(gen_mod).

-export([start/2,
  stop/1,
  on_user_send_packet/3]).

-define(PROCNAME, ?MODULE).

-include("ejabberd.hrl").
-include("jlib.hrl").
-include("logger.hrl").

%% start(Host, Opts) ->
%%     %%% ?INFO_MSG("Starting mod_offline_post", [] ),
%%     register(?PROCNAME,spawn(?MODULE, init, [Host, Opts])),
%%     ok.

%% init(Host, _Opts) ->
%%     inets:start(),
%%     ssl:start(),
%%     ejabberd_hooks:add(user_send_packet, Host, ?MODULE, send_notice, 10),
%%     ok.

start(Host, _Opts) ->
    %% ?INFO_MSG("mod_user_send_packet_post starting", []),
    inets:start(),
    ssl:start(),
    ejabberd_hooks:add(user_send_packet, Host, ?MODULE, on_user_send_packet, 0),
    ok.

stop(Host) ->
    %% ?INFO_MSG("mod_user_send_packet_post stopping", []),
    ejabberd_hooks:delete(user_send_packet, Host, ?MODULE, on_user_send_packet, 0),
    ok.

on_user_send_packet(From, To, Packet) ->
    forward_packet(From, To, Packet),
    Packet.

forward_packet(From, To, Packet) ->
    Type = xml:get_tag_attr_s(list_to_binary("type"), Packet),
    Body = xml:get_path_s(Packet, [{elem, list_to_binary("body")}, cdata]),
    Token = gen_mod:get_module_opt(To#jid.lserver, ?MODULE, auth_token, fun(S) -> iolist_to_binary(S) end, list_to_binary("")),
    PostUrl = gen_mod:get_module_opt(To#jid.lserver, ?MODULE, post_url, fun(S) -> iolist_to_binary(S) end, list_to_binary("")),

    if (Type == <<"chat">>) and (Body /= <<"">>) ->
	      Sep = "&",
        Post = [
          "to=", To#jid.luser, Sep,
          "from=", From#jid.luser, Sep,
          "body=", url_encode(binary_to_list(Body)), Sep,
          "access_token=", Token],
        httpc:request(post, {binary_to_list(PostUrl), [], "application/x-www-form-urlencoded", list_to_binary(Post)},[],[]),
        ok;
      true ->
        ok
    end.


%%% The following url encoding code is from the yaws project and retains it's original license.
%%% https://github.com/klacke/yaws/blob/master/LICENSE
%%% Copyright (c) 2006, Claes Wikstrom, klacke@hyber.org
%%% All rights reserved.
url_encode([H|T]) when is_list(H) ->
    [url_encode(H) | url_encode(T)];
url_encode([H|T]) ->
    if
        H >= $a, $z >= H ->
            [H|url_encode(T)];
        H >= $A, $Z >= H ->
            [H|url_encode(T)];
        H >= $0, $9 >= H ->
            [H|url_encode(T)];
        H == $_; H == $.; H == $-; H == $/; H == $: -> % FIXME: more..
            [H|url_encode(T)];
        true ->
            case integer_to_hex(H) of
                [X, Y] ->
                    [$%, X, Y | url_encode(T)];
                [X] ->
                    [$%, $0, X | url_encode(T)]
            end
     end;

url_encode([]) ->
    [].

integer_to_hex(I) ->
    case catch erlang:integer_to_list(I, 16) of
        {'EXIT', _} -> old_integer_to_hex(I);
        Int         -> Int
    end.

old_integer_to_hex(I) when I < 10 ->
    integer_to_list(I);
old_integer_to_hex(I) when I < 16 ->
    [I-10+$A];
old_integer_to_hex(I) when I >= 16 ->
    N = trunc(I/16),
    old_integer_to_hex(N) ++ old_integer_to_hex(I rem 16).

