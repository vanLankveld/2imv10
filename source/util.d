module _2imv10.util;

import std.stdio;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.memory;
import core.stdc.string;
import derelict.opengl3.gl3;
import derelict.glfw3.glfw3;

const uint FOURCC_DXT1 = 0x31545844; // Equivalent to "DXT1" in ASCII
const uint FOURCC_DXT3 =  0x33545844; // Equivalent to "DXT3" in ASCII
const uint FOURCC_DXT5 =  0x35545844; // Equivalent to "DXT5" in ASCII

GLuint loadDDS(const char * imagepath){

	char[124] header;

	FILE *fp;

	/* try to open the file */
	fp = fopen(imagepath, "rb");
	if (fp == null){
		printf("%s could not be opened. Are you in the right directory ? Don't forget to read the FAQ !\n", imagepath); getchar();
		return 0;
	}

	/* verify the type of file */
	char[4] filecode;
	fread(cast(void*)filecode, 1, 4, fp);
	if (strncmp(cast(const(char*))filecode, cast(const(char*))"DDS ", 4) != 0) {
		fclose(fp);
		return 0;
	}

	/* get the surface desc */
	fread(&header, 124, 1, fp);

	uint height      = *cast(uint*)&(header[8 ]);
	uint width	     = *cast(uint*)&(header[12]);
	uint linearSize	 = *cast(uint*)&(header[16]);
	uint mipMapCount = *cast(uint*)&(header[24]);
	uint fourCC      = *cast(uint*)&(header[80]);


	char * buffer;
	uint bufsize;
	/* how big is it going to be including all mipmaps? */
	bufsize = mipMapCount > 1 ? linearSize * 2 : linearSize;
	buffer = cast(char*) malloc(bufsize * char.sizeof);
	fread(buffer, 1, bufsize, fp);
	/* close the file pointer */
	fclose(fp);

	uint components  = (fourCC == FOURCC_DXT1) ? 3 : 4;
	uint format;
	switch(fourCC)
	{
	case FOURCC_DXT1:
		format = GL_COMPRESSED_RGBA_S3TC_DXT1_EXT;
		break;
	case FOURCC_DXT3:
		format = GL_COMPRESSED_RGBA_S3TC_DXT3_EXT;
		break;
	case FOURCC_DXT5:
		format = GL_COMPRESSED_RGBA_S3TC_DXT5_EXT;
		break;
	default:
		free(buffer);
		return 0;
	}

	// Create one OpenGL texture
	GLuint textureID;
	glGenTextures(1, &textureID);

	// "Bind" the newly created texture : all future texture functions will modify this texture
	glBindTexture(GL_TEXTURE_2D, textureID);
	glPixelStorei(GL_UNPACK_ALIGNMENT,1);

	uint blockSize = (format == GL_COMPRESSED_RGBA_S3TC_DXT1_EXT) ? 8 : 16;
	uint offset = 0;

	/* load the mipmaps */
	for (uint level = 0; level < mipMapCount && (width || height); ++level)
	{
		uint size = ((width+3)/4)*((height+3)/4)*blockSize;
		glCompressedTexImage2D(GL_TEXTURE_2D, level, format, width, height,
			0, size, buffer + offset);

		offset += size;
		width  /= 2;
		height /= 2;

		// Deal with Non-Power-Of-Two textures. This code is not included in the webpage to reduce clutter.
		if(width < 1) width = 1;
		if(height < 1) height = 1;

	}

	free(buffer);

	return textureID;


}