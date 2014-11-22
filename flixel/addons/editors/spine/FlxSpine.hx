package flixel.addons.editors.spine;

#if FLX_RENDER_TILE
import flixel.graphics.tile.FlxDrawTrianglesItem;
#end

import flixel.addons.editors.spine.texture.FlixelTexture;
import flixel.addons.editors.spine.texture.FlixelTextureLoader;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.FlxStrip;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.frames.FlxImageFrame;
import flixel.math.FlxAngle;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.util.FlxColor;
import haxe.ds.ObjectMap;
import openfl.display.Bitmap;
import openfl.display.Graphics;
import openfl.display.Sprite;
import openfl.Assets;
import openfl.display.BitmapData;
import openfl.display.BlendMode;
import openfl.Vector;
import spinehaxe.animation.AnimationState;
import spinehaxe.animation.AnimationStateData;
import spinehaxe.atlas.Atlas;
import spinehaxe.atlas.AtlasRegion;
import spinehaxe.attachments.Attachment;
import spinehaxe.attachments.MeshAttachment;
import spinehaxe.attachments.RegionAttachment;
import spinehaxe.attachments.AtlasAttachmentLoader;
import spinehaxe.attachments.SkinnedMeshAttachment;
import spinehaxe.Bone;
import spinehaxe.Skeleton;
import spinehaxe.SkeletonData;
import spinehaxe.SkeletonJson;
import spinehaxe.Slot;

/**
 * A Sprite that can play animations exported by Spine (http://esotericsoftware.com/)
 * 
 * @author Big thanks to the work on spinehx by nitrobin (https://github.com/nitrobin/spinehx).
 * HaxeFlixel Port by: Sasha (Beeblerox), Sam Batista (crazysam), Kuris Makku (xraven13)
 * 
 * The current version is using https://github.com/bendmorris/spinehaxe
 * since the original lib by nitrobin isn't supported anymore.
 */
class FlxSpine extends FlxSprite
{
	/**
	 * Get Spine animation data.
	 * 
	 * @param	DataName	The name of the animation data files exported from Spine (.atlas .json .png).
	 * @param	DataPath	The directory these files are located at
	 * @param	Scale		Animation scale
	 */
	public static function readSkeletonData(DataName:String, DataPath:String, Scale:Float = 1):SkeletonData
	{
		if (DataPath.lastIndexOf("/") < 0) DataPath += "/"; // append / at the end of the folder path
		var spineAtlas:Atlas = new Atlas(Assets.getText(DataPath + DataName + ".atlas"), new FlixelTextureLoader(DataPath));
		var json:SkeletonJson = new SkeletonJson(new AtlasAttachmentLoader(spineAtlas));
		json.scale = Scale;
		var skeletonData:SkeletonData = json.readSkeletonData(Assets.getText(DataPath + DataName + ".json"), DataName);
		return skeletonData;
	}
	
	public var skeleton:Skeleton;
	public var skeletonData:SkeletonData;
	public var state:AnimationState;
	public var stateData:AnimationStateData;
	
	/**
	 * Helper FlxObject, which you can use for colliding with other flixel objects.
	 * Collider have additional offsetX and offsetY properties which helps you to adjust hitbox.
	 * Change of position of this sprite causes change of collider's position and vice versa.
	 * But you should apply velocity and acceleration to collider rather than to this spine sprite.
	 */
	public var collider(default, null):FlxSpineCollider;
	
	public var renderMeshes(default, null):Bool = false;
	
	private var bounds:FlxRect;
	private var cameraBounds:FlxRect;
	
	private var _tempVertices:Vector<Float>;
	private var _quadTriangles:Vector<Int>;
	
	/**
	 * Instantiate a new Spine Sprite.
	 * @param	skeletonData	Animation data from Spine (.json .skel .png), get it like this: FlxSpineSprite.readSkeletonData( "mySpriteData", "assets/" );
	 * @param	X				The initial X position of the sprite.
	 * @param	Y				The initial Y position of the sprite.
	 * @param	Width			The maximum width of this sprite (avoid very large sprites since they are performance intensive).
	 * @param	Height			The maximum height of this sprite (avoid very large sprites since they are performance intensive).
	 * @param	renderMeshes	If true, then graphic will be rendered with drawTriangles(), if false (by default), then it will be rendered with drawTiles().
	 */
	public function new(skeletonData:SkeletonData, X:Float = 0, Y:Float = 0, Width:Float = 0, Height:Float = 0, OffsetX:Float = 0, OffsetY:Float = 0, renderMeshes:Bool = false)
	{
		super(X, Y);
		
		width = Width;
		height = Height;
		
		this.skeletonData = skeletonData;
		
		stateData = new AnimationStateData(skeletonData);
		state = new AnimationState(stateData);
		
		skeleton = new Skeleton(skeletonData);
		skeleton.x = 0;
		skeleton.y = 0;
		
		flipX = false;
		flipY = true;
		
		collider = new FlxSpineCollider(this, X, Y, Width, Height, OffsetX, OffsetY);
		
		setPosition(x, y);
		setSize(width, height);
		
		this.renderMeshes = renderMeshes;
		
		bounds = new FlxRect();
		cameraBounds = new FlxRect();
		
		_tempVertices = new Vector<Float>(8);
		
		_quadTriangles = new Vector<Int>();
		_quadTriangles[0] = 0;// = Vector.fromArray([0, 1, 2, 2, 3, 0]);
		_quadTriangles[1] = 1;
		_quadTriangles[2] = 2;
		_quadTriangles[3] = 2;
		_quadTriangles[4] = 3;
		_quadTriangles[5] = 0;
	}
	
	override public function destroy():Void
	{
		if (collider != null)
			collider.destroy();
		collider = null;
		
		skeletonData = null;
		skeleton = null;
		state = null;
		stateData = null;
		
		bounds = null;
		cameraBounds = null;
		
		_tempVertices = null;
		_quadTriangles = null;
		
		super.destroy();
	}
	
	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		
		state.update(elapsed);
		state.apply(skeleton);
		skeleton.updateWorldTransform();
	}
	
	/**
	 * Called by game loop, updates then blits or renders current frame of animation to the screen
	 */
	override public function draw():Void
	{
		if (alpha == 0)
		{
			return;
		}
		
		if (renderMeshes)
		{
			renderWithTriangles();
		}
		else
		{
			renderWithQuads();	
		}
		
		collider.draw();
	}
	
	private function renderWithTriangles():Void
	{
		var drawOrder:Array<Slot> = skeleton.drawOrder;
		var i:Int = 0, n:Int = drawOrder.length;
		var graph:FlxGraphic = null;
		var wrapper:FlxStrip;
		var worldVertices:Vector<Float> = _tempVertices;
		var triangles:Vector<Int> = null;
		var uvs:Vector<Float> = null;
		var verticesLength:Int;
		
		while (i < n) 
		{
			var slot:Slot = drawOrder[i];
			
			if (slot.attachment != null)
			{
				wrapper = null;
				
				if (Std.is(slot.attachment, RegionAttachment))
				{
					var region:RegionAttachment = cast slot.attachment;
					verticesLength = 8;
					if (worldVertices.length < verticesLength) worldVertices.length = verticesLength;
					region.computeWorldVertices(0, 0, slot.bone, worldVertices);
					uvs = region.uvs;
					triangles = _quadTriangles;
					
					if (Std.is(region.rendererObject, FlxStrip))
					{
						wrapper = cast region.rendererObject;
					}
					else
					{
						var atlasRegion:AtlasRegion = cast region.rendererObject;
						var bitmapData:BitmapData = cast(atlasRegion.page.rendererObject, BitmapData);
						wrapper = new FlxStrip(0, 0, bitmapData);
						region.rendererObject = wrapper;
					}
				} 
				
				else if (Std.is(slot.attachment, MeshAttachment)) 
				{
					var mesh:MeshAttachment = cast(slot.attachment, MeshAttachment);
					verticesLength = mesh.vertices.length;
					if (worldVertices.length < verticesLength) worldVertices.length = verticesLength;
					mesh.computeWorldVertices(x, y, slot, worldVertices);
					uvs = mesh.uvs;
					triangles = mesh.triangles;
					
					if (Std.is(mesh.rendererObject, FlxStrip))
					{
						wrapper = cast mesh.rendererObject;
					}
					else
					{
						var atlasRegion:AtlasRegion = cast mesh.rendererObject;
						var bitmapData:BitmapData = cast(atlasRegion.page.rendererObject, BitmapData);
						wrapper = new FlxStrip(0, 0, bitmapData);
						mesh.rendererObject = wrapper;
					}
				}
				else if (Std.is(slot.attachment, SkinnedMeshAttachment))
				{
					var skinnedMesh:SkinnedMeshAttachment = cast(slot.attachment, SkinnedMeshAttachment);
					verticesLength = skinnedMesh.uvs.length;
					if (worldVertices.length < verticesLength) worldVertices.length = verticesLength;
					skinnedMesh.computeWorldVertices(x, y, slot, worldVertices);
					uvs = skinnedMesh.uvs;
					triangles = skinnedMesh.triangles;
					
					if (Std.is(skinnedMesh.rendererObject, FlxStrip))
					{
						wrapper = cast skinnedMesh.rendererObject;
					}
					else
					{
						var atlasRegion:AtlasRegion = cast skinnedMesh.rendererObject;
						var bitmapData:BitmapData = cast(atlasRegion.page.rendererObject, BitmapData);
						wrapper = new FlxStrip(0, 0, bitmapData);
						skinnedMesh.rendererObject = wrapper;
					}
				}
				
				if (wrapper != null)
				{
					wrapper.x = x;
					wrapper.y = y;
					wrapper.cameras = cameras;
					
					wrapper.vertices = worldVertices;
					wrapper.indices = triangles;
					wrapper.uvs = uvs;
					wrapper.draw();
				}
			}
			
			i++;
		}
	}
	
	private inline function pushVertex(vx:Float, vy:Float, camera:FlxCamera, vs:Vector<Float>):Void
	{
		#if FLX_RENDER_TILE
		vx *= camera.totalScaleX;
		vy *= camera.totalScaleY;
		#end
		
		vs.push(vx);
		vs.push(vy);
	}
	
	private function inflateBounds(x:Float, y:Float):Void 
	{
		if (x < bounds.x) 
		{
			bounds.width += bounds.x - x;
			bounds.x = x;
		}
		
		if (y < bounds.y) 
		{
			bounds.height += bounds.y - y;
			bounds.y = y;
		}
		
		if (x > bounds.x + bounds.width) 
		{
			bounds.width = x - bounds.x;
		}
		
		if (y > bounds.y + bounds.height) 
		{
			bounds.height = y - bounds.y;
		}
	}
	
	private function renderWithQuads():Void
	{
		var flipX:Int = skeleton.flipX ? -1 : 1;
		var flipY:Int = skeleton.flipY ? 1 : -1;
		var flip:Int = flipX * flipY;
		
		var drawOrder:Array<Slot> = skeleton.drawOrder;
		var i:Int = 0, n:Int = drawOrder.length;
		
		while (i < n) 
		{
			var slot:Slot = drawOrder[i];
			if (slot.attachment == null)
			{
				i++;
				continue;
			}
			
			var regionAttachment:RegionAttachment = cast slot.attachment;
			if (regionAttachment != null) 
			{
				var wrapper:FlxSprite = getSprite(regionAttachment);
				wrapper.blend = slot.data.additiveBlending ? BlendMode.ADD : BlendMode.NORMAL;
				
				wrapper.color = FlxColor.fromRGBFloat(skeleton.r * slot.r * regionAttachment.r * color.redFloat,
				                                      skeleton.g * slot.g * regionAttachment.g * color.greenFloat,
												      skeleton.b * slot.b * regionAttachment.b * color.blueFloat);
				
				wrapper.alpha = skeleton.a * slot.a * regionAttachment.a * this.alpha;
				
				var bone:Bone = slot.bone;
				
				var wrapperAngle:Float = wrapper.angle;
				var wrapperScaleX:Float = wrapper.scale.x;
				var wrapperScaleY:Float = wrapper.scale.y;
				
				var wrapperOriginX:Float = wrapper.origin.x;
				var wrapperOriginY:Float = wrapper.origin.y;
				
				var worldRotation:Float = -bone.worldRotation;
				var worldScaleX:Float = bone.worldScaleX;
				var worldScaleY:Float = bone.worldScaleY;
				
				wrapper.origin.set(0, 0);
				
				_matrix.identity();
				_matrix.translate(wrapperOriginX, wrapperOriginY);
				_matrix.scale(worldScaleX, worldScaleY);
				_matrix.rotate(worldRotation * Math.PI / 180);
				
				wrapper.angle += worldRotation;
				wrapper.angle *= flip;
				wrapper.scale.x *= worldScaleX * flipX;
				wrapper.scale.y *= worldScaleY * flipY;
				
				wrapper.x = this.x + bone.worldX + _matrix.tx * flipX;
				wrapper.y = this.y + bone.worldY + _matrix.ty * flipY;
				
				wrapper.antialiasing = antialiasing;
				wrapper.visible = true;
				wrapper.draw();
				
				wrapper.angle = wrapperAngle;
				wrapper.scale.set(wrapperScaleX, wrapperScaleY);
				wrapper.origin.set(wrapperOriginX, wrapperOriginY);
			}	
			
			i++;
		}
	}
	
	#if !FLX_NO_DEBUG
	override public function drawDebugOnCamera(Camera:FlxCamera):Void
	{
		super.drawDebugOnCamera(Camera);
		
		collider.drawDebugOnCamera(Camera);
		
		var drawOrder:Array<Slot> = skeleton.drawOrder;
		for (slot in drawOrder) 
		{
			var attachment:Attachment = slot.attachment;
			if (Std.is(attachment, RegionAttachment)) 
			{
				var regionAttachment:RegionAttachment = cast attachment;
				var wrapper:FlxSprite = getSprite(regionAttachment);
				wrapper.drawDebugOnCamera(Camera);
			}
		}
	}
	#end
	
	private function getSprite(regionAttachment:RegionAttachment):FlxSprite 
	{
		if (regionAttachment.wrapperSprite != null)
		{
			return cast(regionAttachment.wrapperSprite, FlxSprite);
		}
		
		var region:AtlasRegion = cast regionAttachment.rendererObject;
		var bitmapData:BitmapData = cast(region.page.rendererObject, BitmapData);
		
		var regionWidth:Float = region.rotate ? region.height : region.width;
		var regionHeight:Float = region.rotate ? region.width : region.height;
		
		var graph:FlxGraphic = FlxG.bitmap.add(bitmapData);
		var atlasFrames:FlxAtlasFrames = (graph.atlasFrames == null) ? new FlxAtlasFrames(graph) : graph.atlasFrames;
		
		var name:String = region.name;
		var offset:FlxPoint = FlxPoint.get(0, 0);
		var frameRect:FlxRect = new FlxRect(region.x, region.y, regionWidth, regionHeight);
		
		var sourceSize:FlxPoint = FlxPoint.get(frameRect.width, frameRect.height);
		var imageFrame = FlxImageFrame.fromFrame(atlasFrames.addAtlasFrame(frameRect, sourceSize, offset, name));
		
		var wrapper:FlxSprite = new FlxSprite();
		wrapper.frames = imageFrame;
		wrapper.antialiasing = antialiasing;
		
		wrapper.angle = -regionAttachment.rotation;
		wrapper.scale.x = regionAttachment.scaleX * (regionAttachment.width / region.width);
		wrapper.scale.y = regionAttachment.scaleY * (regionAttachment.height / region.height);

		// Position using attachment translation, shifted as if scale and rotation were at image center.
		var radians:Float = -regionAttachment.rotation * Math.PI / 180;
		var cos:Float = Math.cos(radians);
		var sin:Float = Math.sin(radians);
		var shiftX:Float = -regionAttachment.width / 2 * regionAttachment.scaleX;
		var shiftY:Float = -regionAttachment.height / 2 * regionAttachment.scaleY;
		
		if (region.rotate) 
		{
			wrapper.angle += 90;
			shiftX += regionHeight * (regionAttachment.width / region.width);
		}
		
		wrapper.origin.x = regionAttachment.x + shiftX * cos - shiftY * sin;
		wrapper.origin.y = -regionAttachment.y + shiftX * sin + shiftY * cos;
		regionAttachment.wrapperSprite = wrapper;
		return wrapper;
	}
	
	override function set_x(NewX:Float):Float 
	{
		super.set_x(NewX);
		
		if (skeleton != null && collider != null)
		{
			if (skeleton.flipX)
			{
				collider.x = x - collider.offsetX - width;
			}
			else
			{
				collider.x = x + collider.offsetX;
			}
		}
		
		return NewX;
	}
	
	override function set_y(NewY:Float):Float 
	{
		super.set_y(NewY);
		
		if (skeleton != null && collider != null)
		{
			if (skeleton.flipY)
			{
				collider.y = y + collider.offsetY - height;
			}
			else
			{
				collider.y = y - collider.offsetY;
			}
		}
		
		return NewY;
	}
	
	override function set_width(Width:Float):Float 
	{
		super.set_width(Width);
		
		if (skeleton != null && collider != null)
		{
			collider.width = Width;
		}
		
		return Width;
	}
	
	override function set_height(Height:Float):Float 
	{
		super.set_height(Height);
		
		if (skeleton != null && collider != null)
		{
			collider.height = Height;
		}
		
		return Height;
	}
	
	override private function set_flipX(value:Bool):Bool
	{
		skeleton.flipX = value;
		set_x(x);
		return flipX = value;
	}
	
	override private function set_flipY(value:Bool):Bool
	{
		skeleton.flipY = value;
		set_y(y);
		return flipY = value;
	}
}

class FlxSpineCollider extends FlxObject
{
	public var offsetX(default, set):Float = 0;
	public var offsetY(default, set):Float = 0;
	
	public var parent(default, null):FlxSpine;
	
	public function new(Parent:FlxSpine, X:Float = 0, Y:Float = 0, Width:Float = 0, Height:Float = 0, OffsetX:Float = 0, OffsetY:Float = 0)
	{
		super(X, Y, Width, Height);
		offsetX = OffsetX;
		offsetY = OffsetY;
		parent = Parent;
	}
	
	override public function destroy():Void 
	{
		parent = null;
		super.destroy();
	}
	
	override function set_x(NewX:Float):Float 
	{
		if (parent != null && x != NewX)
		{
			super.set_x(NewX);
			
			if (parent.skeleton.flipX)
			{
				parent.x = NewX + offsetX + width;
			}
			else
			{
				parent.x = NewX - offsetX;
			}
		}
		else
		{
			super.set_x(NewX);
		}
		
		return NewX;
	}
	
	override function set_y(NewY:Float):Float 
	{
		if (parent != null && y != NewY)
		{
			super.set_y(NewY);
			
			if (parent.skeleton.flipY)
			{
				parent.y = NewY - offsetY + height;
			}
			else
			{
				parent.y = NewY + offsetY;
			}
		}
		else
		{
			super.set_y(NewY);
		}
		
		return NewY;
	}
	
	override function set_width(Width:Float):Float 
	{
		if (parent != null && width != Width)
		{
			super.set_width(Width);
			parent.x = parent.x;
		}
		else
		{
			super.set_width(Width);
		}
		
		return Width;
	}
	
	override function set_height(Height:Float):Float 
	{
		if (parent != null && height != Height)
		{
			super.set_height(Height);
			parent.y = parent.y;
		}
		else
		{
			super.set_height(Height);
		}
		
		return Height;
	}
	
	private function set_offsetX(value:Float):Float
	{
		if (parent != null && offsetX != value)
		{
			offsetX = value;
			parent.x = parent.x;
		}
		else
		{
			offsetX = value;
		}
		
		return value;
	}
	
	private function set_offsetY(value:Float):Float
	{
		if (parent != null && offsetY != value)
		{
			offsetY = value;
			parent.y = parent.y;
		}
		else
		{
			offsetY = value;
		}
		
		return value;
	}	
}