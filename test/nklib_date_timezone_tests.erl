-module(nklib_date_timezone_tests).
-include_lib("eunit/include/eunit.hrl").

canadian_conversion_test_() ->
    [?_assertEqual({ok, {{2026,12,1},{13,0,0}}},
                   nklib_date:gmt_to_local_calendar({{2026,12,1},{20,0,0}}, <<"America/Vancouver">>))
    ,?_assertEqual({ok, {{2026,12,1},{20,0,0}}},
                   nklib_date:local_to_gmt_calendar({{2026,12,1},{13,0,0}}, <<"America/Vancouver">>))
    ,?_assertEqual({ok, {{2026,1,15},{12,0,0}}},
                   nklib_date:gmt_to_local_calendar({{2026,1,15},{20,0,0}}, <<"America/Vancouver">>))
    ,?_assertEqual({ok, {{2026,12,1},{14,0,0}}},
                   nklib_date:gmt_to_local_calendar({{2026,12,1},{20,0,0}}, <<"America/Edmonton">>))
    ].

gap_overlap_test_() ->
    [?_assertEqual({error, time_not_exists},
                   nklib_date:local_to_gmt_calendar({{2027,3,14},{2,30,0}}, <<"America/New_York">>))
    ,?_assertEqual({ok, {{2026,11,1},{6,30,0}}},
                   nklib_date:local_to_gmt_calendar({{2026,11,1},{1,30,0}}, <<"America/New_York">>))
    ,?_assertEqual({error, unknown_tz},
                   nklib_date:gmt_to_local_calendar({{2026,12,1},{20,0,0}}, <<"Unknown/Zone">>))
    ].

os_inventory_test() ->
    ok = nklib_date:store_timezones(),
    ?assert(nklib_date:is_valid_timezone(<<"America/Vancouver">>)),
    ?assert(nklib_date:is_valid_timezone(<<"Canada/Pacific">>)),
    ?assertNot(nklib_date:is_valid_timezone(<<"Unknown/Zone">>)),
    ?assertNot(nklib_date:is_valid_timezone(<<"localtime">>)),
    ?assertEqual({ok, <<"GMT">>}, nklib_date:syntax_timezone(<<>>)).
