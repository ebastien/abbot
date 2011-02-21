# Spriting support.
#
# The sprite method performs the spriting. It creates collections of
# images to sprite and then calls layout_sprite and generate_sprite.
#
# The layout_sprite method arranges the slices, defining their positions
# within the sprites.
#
# The generate_sprite method combines the slices into an image.
module Chance

  class Instance
    # The Spriting module handles sorting slices into sprites, laying them
    # out within the sprites, and generating the final sprite images.
    module Spriting
      # Performs the spriting process on all of the @slices, creating sprite
      # images in the class's @sprites property and updating the individual slices 
      # with a :sprite property containing the identifier of the sprite, and offset
      # properties for the offsets within the image.
      def sprite
        
      end

      # Determines the appropriate sprite for each slice, creating it if necessary,
      # and puts the slice into that sprite. The appropriate sprite may differ based
      # on the slice's repeat settings, for instance.
      def group_slices_into_sprites
        @slices.each do |key, slice|
          sprite = sprite_for_slice(slice)
          sprite.slices << slice
        end
      end

      # Returns the sprite to use for the given slice, creating the sprite if needed.
      # The sprite could differ based on repeat settings or file type, for instance.
      def sprite_for_slice(slice)
        sprite_name = sprite_name_for_slice(slice)

        if sprites[sprite_name].nil?
          sprite = {
            :name => sprite_name,
            :slices => [],

            # The sprite will use horizontal layout under repeat-y, where images
            # must stretch all the way from the top to the bottom
            :use_horizontal_layout => slice[:repeat] == "repeat-y" ? false : true
          }
        end

        return sprites[sprite_name]
      end

      # Determines the name of the sprite for the given slice. The sprite
      # by this name may not exist yet.
      def sprite_name_for_slice(slice)
        return slice[:repeat] + File.extname(slice[:path])
      end

      # Performs the layout operation, laying either up-to-down, or "
      # (for repeat-y slices) left-to-right.
      def layout_slices_in_sprite(sprite)
        # The position is the position in the layout direction. In vertical mode
        # (the usual) it is the Y position.
        pos = 0

        # The size is the current size of the sprite in the non-layout direction;
        # for example, in the usual, vertical mode, the size is the width.
        #
        # Usually, this is computed as a simple max of itself and the width of any
        # given slice. However, when repeating, the least common multiple is used,
        # and the smallest item is stored as well.
        size = 0
        smallest_size = nil

        is_horizontal = sprite[:use_horizontal_layout]

        sprite.slices.each do |slice|
          # We must find a canvas either on the slice (if it was actually sliced),
          # or on the slice's file. Otherwise, we're in big shit.
          canvas = slice[:canvas] || slice[:file][:canvas]

          # TODO: MAKE A BETTER ERROR.
          unless canvas
            throw "Could not sprite image " + slice[:path] + "; if it is not a PNG"
          end

          # RMagick has a different API than ChunkyPNG; we have to detect
          # which one we are using, and use the correct API accordingly.
          if canvas.respond_to?('columns')
            slice_width = canvas.columns
            slice_height = canvas.rows
          else
            slice_width = canvas.width
            slice_height = canvas.height
          end

          slice_length = is_horizontal ? slice_width : slice_height
          slice_size = is_horizontal ? slice_height : slice_width

          # When repeating, we must use the least common multiple so that
          # we can ensure the repeat pattern works even with multiple repeat
          # sizes. However, we should take into account how much extra we are
          # adding by tracking the smallest size item as well.
          if slice[:repeat] != "no-repeat"
            smallest_size = slice_size if smallest_size.nil?
            smallest_size = [slice_size, smallest_size].min

            size = size.lcm slice_size
          else
            size = [size, slice_size].max
          end

          # We have extras for manual tweaking of offsetx/y. We have to make sure there
          # is padding for this (on either side)
          #
          # We have to add room for the minimum offset by adding to the end, and add
          # room for the max by adding to the front. We only care about it in our
          # layout direction. Otherwise, the slices are flush to the edge, so it won't
          # matter.
          if slice[:min_offset_x] < 0 and is_horizontal
            slice_length -= slice[:min_offset_x]
          elsif slice[:min_offset_y] < 0 and not is_horizontal
            slice_length -= slice[:min_offset_y]
          end

          if slice[:max_offset_x] > 0 and is_horizontal
            pos += slice[:max_offset_x]
          elsif slice[:max_offset_y] > 0 and not is_horizontal
            pos += slice[:max_offset_y]
          end


          slice[:sprite_slice_x] = is_horizontal ? pos : 0
          slice[:sprite_slice_y] = is_horizontal ? 0 : pos
          slice[:sprite_slice_width] = slice_width
          slice[:sprite_slice_height] = slice_height

          pos += slice_length
        end

        # TODO: USE A CONSTANT FOR THIS WARNING
        if size - smallest_size > 10
          puts "WARNING: Used more than 10 extra rows or columns to accomdate repeating slices."
          puts "Wasted up to " + (pos * size-smallest_size).to_s + " pixels"
        end

        sprite[:width] = is_horizontal ? pos : size
        sprite[:height] = is_horizontal ? size : pos

      end


      # Generates the image for the specified sprite, putting it in the sprite's 
      # :image property.
      def generate_sprite(sprite)
        canvas = canvas_for_sprite(sprite)
        sprite[:canvas] = canvas

        sprite[:slices].each do |slice|
          x = slice[:sprite_slice_x]
          y = slice[:sprite_slice_y]
          width = slice[:sprite_slice_width]
          height = slice[:sprite_slice_height]

          # If it repeats, it needs to go edge-to-edge in one direction
          if slice[:repeat] == 'repeat-y'
            height = sprite[:height]
          end

          if slice[:repeat] == 'repeat-x'
            width = sprite[:width]
          end

          compose_canvas_on_target(canvas, slice[:canvas], x, y, width, height)
        end
      end

      def canvas_for_sprite(sprite)
        # If we require RMagick, we should have already loaded it, so we don't
        # need to worry over that at the moment.
        if sprite[:name] =~ /\.(gif|jpg)/
          return Magick::Image.new (sprite[:width], sprite[:height])
        else
          return ChunkyPNG::Image.new(sprite[:width], sprite[:height], ChunkyPNG::Color::TRANSPARENT)
        end
      end

      # Writes a slice to the target canvas, repeating it as necessary to fill the width/height.
      def compose_slice_on_canvas(target, slice, x, y, width, height)
        source_canvas = slice[:canvas] || slice[:file][:canvas]
        source_width = slice[:sprite_slice_width]
        source_height = slice[:sprite_slice_height]

        top = 0
        left = 0

        # Repeat the pattern to fill the width/height.
        while top < height do
          while left < width do
            if target.respond_to?(:compose)
              target.compose!(source_canvas, left, top)
            else
              target.composite!(source_canvas, left, top)
            end
            left += source_width
          end
          top += source_height
        end

      end

    end
  end
end