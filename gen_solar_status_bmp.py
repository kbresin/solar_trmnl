from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import argparse

import datetime
from datetime import datetime

project_dir = Path(__file__).parent

def get_kwh(s):
  (value, unit) = s.split(' ')
  unit = unit.lower()
  if unit == 'mwh':
    return float(value) * 1000
  if unit == 'gwh':
    return float(value) * 1000000
  if unit in 'kwh':
    return float(value)
  print("Unknown unit, just returning the value")
  return float(value)

def round_for_display(s):
  """Round an energy string like '174.60 kWh' for at-a-glance display.

  Larger magnitudes carry fewer decimals (spurious precision is noise on
  e-ink), and trailing zeros are stripped so we never show '20.0' or '375.00'.
  """
  try:
    (value_str, unit) = s.split(' ')
    value = float(value_str)
  except ValueError:
    return s
  if abs(value) >= 100:
    decimals = 0
  elif abs(value) >= 10:
    decimals = 1
  else:
    decimals = 2
  value_str = f"{value:.{decimals}f}"
  if '.' in value_str:
    value_str = value_str.rstrip('0').rstrip('.')
  return f"{value_str} {unit}"

local_now = str(datetime.now())
# 2020-03-03 09:51:38.570162+01:00
shorter_time = ':'.join(local_now.split(':')[0:2])
# 2020-03-03 09:51

KWH_TO_CO2_LB=411784.0/265930.0
KWH_TO_DOLLAR=0.085


parser = argparse.ArgumentParser()
parser.add_argument("--daily-output", required=True)
parser.add_argument("--lifetime-output", required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()

lifetime_kwh = get_kwh(args.lifetime_output)
lifetime_co2_lbs = int(lifetime_kwh * KWH_TO_CO2_LB)
lifetime_dollars = int(lifetime_kwh * KWH_TO_DOLLAR)

# Create a monochrome all white image
# trmnl pixel resolution is 800x480 
img = Image.new('1', (800, 480), color='white')

# Initialize ImageDraw
draw = ImageDraw.Draw(img)

# Add logo to the top left
LOGO_FILE = 'green_team_logo_325_sun.png'
logo = Image.open(project_dir / LOGO_FILE)  # Your image file here
#logo = logo.resize((100, 100))
#img.paste(logo, (550, 5))
img.paste(logo, (470, 5))

# Draw some text
# Gidole is a OS font from google
font_ttf = Path.home() / '.local' / 'share' / 'fonts' / 'Gidole-Regular.ttf'
if not font_ttf.exists():
    raise FileNotFoundError(f"Font not found: {font_ttf}\nRun ./setup.sh to download it.")

# initial offset
hdr_offset_x = 10
hdr_offset_y = 5

# title
title_font = ImageFont.truetype(font_ttf, 60)
draw.text((hdr_offset_x, hdr_offset_y), "GLC Solar Array", fill='black', font=title_font)
hdr_offset_x += 20
hdr_offset_y += 87

# headers and data
hdr_font = ImageFont.truetype(font_ttf, 50)
data_font = ImageFont.truetype(font_ttf, 42)

# energy production
draw.text((hdr_offset_x, hdr_offset_y), "Energy Production:", fill='black', font=hdr_font)
hdr_offset_x += 20
hdr_offset_y += 60
draw.text((hdr_offset_x, hdr_offset_y), "  Yesterday: "+round_for_display(args.daily_output), fill='black', font=data_font)
hdr_offset_y += 48
draw.text((hdr_offset_x, hdr_offset_y), "  Lifetime: "+round_for_display(args.lifetime_output), fill='black', font=data_font)
hdr_offset_y += 78

# co2 saved
hdr_offset_x -= 20
draw.text((hdr_offset_x, hdr_offset_y), "Lifetime Savings:", fill='black', font=hdr_font)
hdr_offset_x += 20
hdr_offset_y += 60
draw.text((hdr_offset_x, hdr_offset_y), "  CO2 Reduction: "+'{:,}'.format(lifetime_co2_lbs)+" Pounds", fill='black', font=data_font)
hdr_offset_y += 48
draw.text((hdr_offset_x, hdr_offset_y), "  Cost Savings: $"+'{:,}'.format(lifetime_dollars), fill='black', font=data_font)

# ts
ts_font = ImageFont.truetype(font_ttf, 16)
draw.text((600, 450), "Updated: "+shorter_time,  fill='black', font=ts_font)


# Save as BMP
img.save(args.output)
