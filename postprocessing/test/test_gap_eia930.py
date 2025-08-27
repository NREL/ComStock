import os
import pytest
import logging

import comstockpostproc.gap.eia930

def test_eia930_reference_data():
    ref_data = comstockpostproc.gap.eia930.EIA930().reference_data
    print(ref_data.columns)


def test_eia930_data():
    data = comstockpostproc.gap.eia930.EIA930().data
    print(data)
    
def test_bad_year():
    with pytest.raises(SystemExit) as e:
        data = comstockpostproc.gap.eia930.EIA930(year=2023)
    assert e.type == SystemExit
    assert e.value.code == 1

# def test_reload(caplog):
#     caplog.set_level(logging.INFO)
#     data = comstockpostproc.gap.eia930.EIA930(reload_from_csv=True).data
