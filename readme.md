`Myway` is a minimalistic software for displaying results of photoshoots (or other organised collections of images) to a limited number of users.

# Key concepts

`Myway` displays images from a gallery that belongs to a collection:
 * **a collection** contains galleries; it is a top-level "namespace", separate from other collections
 * **a gallery** belongs to a single collection; it contains images that are displayed together
 * **an image** is a single image file that belongs to a single gallery
 
How does it look in practice:
 * a collection corresponds to a yaml file in `collections` directory; that yaml defines source directory for galleries, name and title, password and other things; when a collection is first accessed, a directory named after the collection will be created inside `collections` and will store all the relevant metadata 
 * a gallery is a directory within the source of the collection; its details can be specified in the gallery yaml file, which is located in the gallery's directory in `collections` 
 * images are, well, image files located directly in the gallery folder; a metadata file is created in the gallery's folder under `collections`

# User interaction

`Myway` supports limited user interaction based on user roles: 
 * **a visitor** browses a collection that may leave comments and react to images
 * **an owner** owns the collection and may modify its properties; has access to the admin page of the collection
 * **an admin** is responsible for the entire installation; has access to admin page of the entire installation and all the collections

# Requirements

`Myway` is written in Ruby and uses Sinatra as its web engine. Image Magick is required.

# Yaml files

`Myway` uses files to store its data.

## `collections/.config.yaml`

This file contains all the setup information.
```yaml
  title: "Display title for the site"
  theme: directory_name # located in themes, that directory contains various views; this is the default unless a collection overrides it
  site_description: "Your site's description, displayed when there are no publicly available collections."
  site_information: "Optional text that shows general information, displayed at the bottom of every page."
  admin:
      login: user_login # no other user can have that user login
      name: "Display name of the user"
      password: abc # required, will be created during setup
```

## `collections/{collection_name}/.collection.yaml`

This file defines the galleries, collection title, its allowed users, password, and so on. The name of the collection is already in the filename. It cannot start with a `.`.
```yaml
  title: "Display title for the collection"
  description: "long form description for the collection" # optional
  information: "Collection-specific information displayed at the bottom of every page that belongs to it (i.e. gallery and image)."
  source: /directory/path # note that web server must have read access to this directory
  password: abc # optional, but if present, the collection cannot be accessed unless that password is entered
  owner: owner_login # corresponds to an entry in the users section; optional, when not present, the admin is the owner
  theme: directory_name # optional, defaults to whatever is the system-wide setting
  miniature: # when defined, allows overriding default miniature setting
    max_width: 320 # change either width or height to 0 to disable miniatures
    max_height: 320
  full: # default "full size" dimensions (original images are not shown in the browser)
    max_width: 2000
    max_height: 1500
  operations:
    allow_visitors: true # if false, no user interaction is allowed, and the option to create a user profile is not allowed
    allow_reactions: true # if false, no reaction buttons are shown
    allow_comments: true # if false, no comment form is shown
    reactions: [] # allowed reactions (shown in reaction buttons - ideally, these are unicode characters)
    allow_downloads: true # if false, users are not able to download the original images (note that the miniature and the "full size" copy can be downloaded)
  visitors:
    - login: user_login
      name: "Display name of the user"
      password: abc # required, will be defined when the user sets up their profile
```

## `collections/{collection_name}/{gallery_name}/.gallery.yaml`

This file contains information related to the gallery. It is automatically created when enabling a collection.
```yaml
  title: "Display title for the gallery" # optional, defaults to the file name
  description: "long form description for the gallery" # optional
```

## `collections/{collection_name}/{gallery_name}/{image_name}.yaml`

Every supported image file in the gallery directory has its own yaml with information about it.
```yaml
  title: "Display title of the image" # obtained first from the filename
  filename: filename.jpg # just the filename
  description: "Long form description of the image"
```

## `collections/{collection_name}/{gallery_name}/{image_name}/reaction.{visitor}.yml`

When visitor accounts and reactions are enabled, this file stores all reactions from the given visitor on the given image.
```yaml
  - reaction: "\U0001F49B" # the reaction made
    login: guest # login of the visitor
    time: 2026-01-01 06:00:00 UTC # timestamp
```

## `collections/{collection_name}/{gallery_name}/{image_name}/comment.{time}.yml`

When visitor accounts and comments are enabled, this file stores a single comment. The `time` in the name corresponds to unix epoch millisecond when the comment was saved.
```yaml
  login: guest # login of the visitor
  name: Guest Person # name of the visitor, as when the comment was posted
  ip: 127.0.0.1 # the ip address
  timestamp: 2026-06-01 08:10:12.725682100 Z # timestamp
  comment: "comment body is here"
  visible: true
```

# Miniatures and "full size"

Miniatures of the original images are created using ImageMagick. The miniature is placed in `public/images/{collection_name}/{gallery_name}/mini.{file_name}.jpg`.
Similarly, full size preview file is created (same place as the miniature, except filename is prefixed with `full.`). The original images are never displayed directly to the visitors (they can only be offered as a download).

# Remarks

This software is free software, released under Apache license. See the `License` file for details.
This software is the result of human work. No line of code was generated by AI.
