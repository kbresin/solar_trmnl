from PIL import Image, ImageDraw, ImageFont

# Create a monochrome all white image
# trmnl pixel resolution is 800x480 
img = Image.new('1', (800, 480), color='white')

# Initialize ImageDraw
draw = ImageDraw.Draw(img)

# Draw some text
fnt = ImageFont.truetype("Gidole-Regular.ttf", 40)  # Make sure this font file exists, or use a default
draw.text((50, 80), "Hello, BMP!", fill='black', font=fnt)

# Paste another image (if needed)
#logo = Image.open('logo.png')  # Your image file here
#logo = logo.resize((100, 100))
#img.paste(logo, (250, 50))

# Save as BMP
img.save('output.bmp')
