"""Regenerate independent 60-digit reference weights for migration tests."""
from decimal import Decimal, getcontext
import json
from pathlib import Path
getcontext().prec = 60
values = [[gap, int(((-Decimal(gap)/20000000).exp()*10**12).to_integral_value())]
          for gap in range(0,100000001,100000)]
Path(__file__).with_name('exp_reference.json').write_text(json.dumps(values))
