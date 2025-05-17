from PIL import Image, ImageDraw, ImageFont
import argparse

import datetime
from datetime import datetime
local_now = str(datetime.now())
# 2020-03-03 09:51:38.570162+01:00
shorter_time = ':'.join(local_now.split(':')[0:2])

print(local_now)
print(shorter_time)
# 2020-03-03 09:51:38.570162+01:00


parser = argparse.ArgumentParser()
parser.add_argument("--daily-output", required=True)
parser.add_argument("--total-output", required=True)
args = parser.parse_args()


# Create a monochrome all white image
# trmnl pixel resolution is 800x480 
img = Image.new('1', (800, 480), color='white')

# Initialize ImageDraw
draw = ImageDraw.Draw(img)

# Draw some text
# Gidole is a OS font from google
font_ttf = 'Gidole-Regular.ttf'

# title
title_font = ImageFont.truetype(font_ttf, 60)
draw.text((10, 10), "GLC Solar Status:", fill='black', font=title_font)

# headers and data
hdr_font = ImageFont.truetype(font_ttf, 30)
hdr_offset = 200
draw.text((hdr_offset, 80), "Yesterday: "+args.daily_output, fill='black', font=title_font)
draw.text((hdr_offset, 160), "Lifetime: "+args.total_output, fill='black', font=title_font)

# status
status_font = ImageFont.truetype(font_ttf, 16)
draw.text((10, 450), "Updated: "+shorter_time,  fill='black', font=status_font)

# Paste another image (if needed)
#logo = Image.open('logo.png')  # Your image file here
#logo = logo.resize((100, 100))
#img.paste(logo, (250, 50))

# Save as BMP
img.save('output.bmp')
