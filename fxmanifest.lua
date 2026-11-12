fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'amassart'
description 'Crowd Manager : spawn and control a crowd of NPCs (MenuV)'
version '1.0.0'

dependencies { 'menuv' }

client_scripts {
    '@menuv/menuv.lua',
    'models.lua',
    'client.lua'
}
