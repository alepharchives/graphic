-module(graphic_demo).

% User API
-export([start/0]).

% Cowboy handler API
-export([init/3, handle/2, terminate/2]).

% Nitrogen callbacks
-include("../include/graphic.hrl").
-export([main/0, body/0]).

% Demo graphic callbacks
-export([time_graphic/0, la_graphic/1, update_la/2]).


start() ->
  %% Start the Process Registry...
  %application:start(nprocreg),

  %% Start Cowboy...
  application:start(mimetypes),
  application:start(cowboy),

  JSStatic = {[<<"js">>, '...'], cowboy_http_static, [{directory, code:lib_dir(graphic, priv)}]},
  NitrogenStatic = {[<<"nitrogen">>, '...'], cowboy_http_static, [{directory, code:lib_dir(nitrogen_core, www)}]},
  GraphicDispatch = {[<<"graphic">>], graphic, []},
  NitrogenDispatch = {[<<"graphic_demo">>], ?MODULE, []},

  Dispatch = [{'_', [JSStatic, NitrogenStatic, GraphicDispatch, NitrogenDispatch]}],
  HttpOpts = [{max_keepalive, 50}, {dispatch, Dispatch}],

  cowboy:start_listener(http, 100,
    cowboy_tcp_transport, [{port, 8880}],
    cowboy_http_protocol, HttpOpts),

  ok.

% Cowboy -> Nitrogen adapter
-record(state, {headers, body}).

init({_Transport, http}, Req, Opts) ->
  Headers = proplists:get_value(headers, Opts, []),
  Body = proplists:get_value(body, Opts, "http_handler"),
  {ok, Req, #state{headers=Headers, body=Body}}.

handle(Req, Opts) ->
  RequestBridge = simple_bridge:make_request(cowboy_request_bridge, {Req, "./priv"}),
  ResponseBridge = simple_bridge:make_response(cowboy_response_bridge, RequestBridge),

  nitrogen:init_request(RequestBridge, ResponseBridge),

  {ok, NewReq} = nitrogen:run(),
  {ok, NewReq, Opts}.

terminate(_Req, _State) ->
  ok.


% Nitrogen page
main() -> #template{file = filename:join([code:lib_dir(graphic, priv), "demo.tmpl"])}.
body() ->
  [
    #panel{style="width:400px;",
      body = #graphic{data = {mfa, ?MODULE, time_graphic, []}} },

    #panel{style="width:400px;",
      body = #graphic{data = {mfa, ?MODULE, la_graphic, [200]}} }
  ].


% Demo graphics
time_graphic() ->
  Now = now_ms(),
  Start = Now - timer:hours(1),
  Times = lists:seq(Start, Now, timer:seconds(1)),

  Config = [
    {option, navigator, minutes},
    {option, legend, true},
    {hours,   [{T, (T div timer:hours(1)) rem 24} || T <- Times]},
    {minutes, [{T, (T div timer:minutes(1)) rem 60} || T <- Times]},
    {seconds, [{T, (T div timer:seconds(1)) rem 60} || T <- Times]} ],
  {ok, Config, undefined, stop}.

la_graphic(Interval) ->
  case lists:keymember(sasl, 3, application:which_applications()) of
    true -> ok;
    false ->
      application:load(sasl),
      application:set_env(sasl, errlog_type, error),
      application:start(sasl)
  end,
  application:start(os_mon),

  Config = [
    {option, navigator, la1},
    {option, legend, true},
    {la1, []},
    {la5, []},
    {la15, []} ],
  timer:send_interval(Interval, update_la),
  {ok, Config, undefined, [{info_handler, update_la}]}.

update_la(update_la, _State) ->
  LA1 = cpu_sup:avg1(),
  LA5 = cpu_sup:avg5(),
  LA15 = cpu_sup:avg15(),
  Now = now_ms(),
  Update = [
    {la1, [{Now, LA1}]},
    {la5, [{Now, LA5}]},
    {la15, [{Now, LA15}]} ],
  {reply, Update}.


now_ms() ->
  now_to_ms(now()).
now_to_ms({MegaSec, Sec, Microsec}) ->
  Microsec div 1000 + (Sec + 1000000*MegaSec) * 1000.

