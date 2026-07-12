# test the doc-build

using CalculusWithJuliaSquared
using Pluto

CalculusWithJuliaSquared.WeaveSupport.weave_all(; build_list=(:html,), force=false)
