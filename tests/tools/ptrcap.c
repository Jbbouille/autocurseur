/* Outil des tests système : forme du pointeur réellement affichée sur l'écran où se trouve
   la souris, telle que Windows la donne au compositeur (duplication d'écran DXGI).

   ptrcap <x> <y> <sortie>
     place la souris en (x, y), capture la forme du pointeur sur l'écran qui contient ce
     point, puis écrit :
       <sortie>.txt : « type largeur hauteur pas point_chaud_x point_chaud_y curseur »
                      (type 1 = monochrome, 2 = couleur, 4 = couleur masquée ;
                       pour une forme monochrome, hauteur = hauteur de l'image, sans le masque ;
                       curseur = identifiant du curseur système affiché, 32512 pour la
                       flèche…, ou 0 si c'est un curseur propre à l'application)
       <sortie>.bin : les octets de la forme (monochrome : masque ET puis OU exclusif)
   Code de sortie : 0 si la forme a été capturée, 1 sinon. */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <stdio.h>
#include <stdlib.h>

static BYTE shape[4 << 20];

/* identifiant du curseur système affiché en ce moment, 0 si aucun */
static unsigned currentSystemCursor(void)
{
    static const unsigned ids[] = {32512, 32513, 32514, 32515, 32516, 32631, 32642, 32643, 32644,
                                   32645, 32646, 32648, 32649, 32650, 32651, 32671, 32672};
    CURSORINFO ci = {sizeof ci};
    if (!GetCursorInfo(&ci)) return 0;
    for (unsigned i = 0; i < sizeof ids / sizeof ids[0]; i++)
        if (LoadCursorW(NULL, MAKEINTRESOURCEW(ids[i])) == ci.hCursor) return ids[i];
    return 0;
}

int main(int argc, char **argv)
{
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    if (argc < 4) return 1;
    int x = atoi(argv[1]), y = atoi(argv[2]);
    SetCursorPos(x, y);
    Sleep(150);
    SetCursorPos(x + 2, y + 1); /* petit mouvement : la fenêtre dessous choisit son curseur */
    Sleep(250);
    POINT p;
    GetCursorPos(&p);

    IDXGIFactory1 *fac;
    if (FAILED(CreateDXGIFactory1(&IID_IDXGIFactory1, (void **)&fac))) return 1;
    IDXGIAdapter1 *ad = NULL;
    IDXGIOutput *out = NULL;
    for (UINT i = 0; !out && IDXGIFactory1_EnumAdapters1(fac, i, &ad) != DXGI_ERROR_NOT_FOUND; i++) {
        IDXGIOutput *o;
        for (UINT j = 0; IDXGIAdapter1_EnumOutputs(ad, j, &o) != DXGI_ERROR_NOT_FOUND; j++) {
            DXGI_OUTPUT_DESC d;
            IDXGIOutput_GetDesc(o, &d);
            RECT r = d.DesktopCoordinates;
            if (p.x >= r.left && p.x < r.right && p.y >= r.top && p.y < r.bottom) {
                out = o;
                break;
            }
            IDXGIOutput_Release(o);
        }
        if (!out) IDXGIAdapter1_Release(ad);
    }
    if (!out) return 1;

    ID3D11Device *dev;
    ID3D11DeviceContext *ctx;
    D3D_FEATURE_LEVEL fl;
    if (FAILED(D3D11CreateDevice((IDXGIAdapter *)ad, D3D_DRIVER_TYPE_UNKNOWN, NULL, 0, NULL, 0, D3D11_SDK_VERSION, &dev, &fl, &ctx))) return 1;
    IDXGIOutput1 *o1;
    if (FAILED(IDXGIOutput_QueryInterface(out, &IID_IDXGIOutput1, (void **)&o1))) return 1;
    IDXGIOutputDuplication *dup;
    if (FAILED(IDXGIOutput1_DuplicateOutput(o1, (IUnknown *)dev, &dup))) return 1;

    for (int i = 0; i < 100; i++) {
        DXGI_OUTDUPL_FRAME_INFO fi;
        IDXGIResource *res = NULL;
        HRESULT hr = IDXGIOutputDuplication_AcquireNextFrame(dup, 100, &fi, &res);
        if (hr == DXGI_ERROR_WAIT_TIMEOUT) {
            SetCursorPos(x + 2 + (i & 1), y + 1); /* provoque une image */
            continue;
        }
        if (FAILED(hr)) return 1;
        if (fi.PointerShapeBufferSize > 0) {
            UINT req;
            DXGI_OUTDUPL_POINTER_SHAPE_INFO si;
            if (FAILED(IDXGIOutputDuplication_GetFramePointerShape(dup, sizeof shape, shape, &req, &si))) return 1;
            UINT h = si.Type == DXGI_OUTDUPL_POINTER_SHAPE_TYPE_MONOCHROME ? si.Height / 2 : si.Height;
            char path[MAX_PATH];
            snprintf(path, sizeof path, "%s.txt", argv[3]);
            FILE *f = fopen(path, "w");
            if (!f) return 1;
            fprintf(f, "%u %u %u %u %ld %ld %u\n", si.Type, si.Width, h, si.Pitch, si.HotSpot.x, si.HotSpot.y,
                    currentSystemCursor());
            fclose(f);
            snprintf(path, sizeof path, "%s.bin", argv[3]);
            f = fopen(path, "wb");
            if (!f) return 1;
            fwrite(shape, 1, si.Pitch * si.Height, f);
            fclose(f);
            return 0;
        }
        if (res) IDXGIResource_Release(res);
        IDXGIOutputDuplication_ReleaseFrame(dup);
    }
    return 1;
}
